// npm test
// Checks T8: Download everything gives a zip of only the member's own data and photos,
// Delete account removes the member, their photos, invitation and codes, the admin cannot
// delete their own account, emails print on this Mac, and the backup keeps the last 3.
// Like the other tests, it runs on a throwaway database in a temporary folder.

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

// Must be set before the database is opened.
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caro-test-'));
process.env.DATA_DIR = dataDir;
delete process.env.NODE_ENV;

const db = require('../src/db');
const app = require('../src/app');
const email = require('../src/lib/email');
const { makeToken, hashToken } = require('../src/lib/auth');
const { now, iso } = require('../src/lib/today');
const { makeBackup, backups, backupDir } = require('../src/jobs/backup');

let server;
let base;
let inviterId;

before(async () => {
  // The admin who sent the invitations.
  inviterId = Number(
    db
      .prepare(`INSERT INTO users (email, name, role, status, onboarding_step, created_at) VALUES ('inviter@example.test', 'Marta', 'admin', 'active', 6, ?)`)
      .run(iso(now())).lastInsertRowid
  );

  server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://localhost:${server.address().port}`;
});

after(() => {
  server.close();
  db.close();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

function request(method, route, token) {
  return fetch(base + route, { method, headers: token ? { Authorization: `Bearer ${token}` } : {} });
}

// A signed-in member with one piece and its two photo files on disk.
let count = 0;
function addMember(role = 'member') {
  count += 1;
  const address = `data${count}@example.test`;
  const at = iso(now());
  const id = Number(
    db
      .prepare(`INSERT INTO users (email, name, role, status, onboarding_step, created_at) VALUES (?, ?, ?, 'active', 6, ?)`)
      .run(address, `Member ${count}`, role, at).lastInsertRowid
  );
  const token = makeToken();
  db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, hashToken(token), at, at);
  db.prepare(`INSERT INTO invitations (name, email, invited_by, status, sent_at, expires_at) VALUES ('x', ?, ?, 'accepted', ?, ?)`).run(
    address,
    inviterId,
    at,
    at
  );
  db.prepare('INSERT INTO login_codes (email, code_hash, created_at, expires_at) VALUES (?, ?, ?, ?)').run(address, 'hash', at, at);

  const folder = path.join(dataDir, 'photos', String(id));
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, `piece${id}.jpg`), 'photo');
  fs.writeFileSync(path.join(folder, `piece${id}-thumb.webp`), 'thumb');
  db.prepare(
    `INSERT INTO pieces (user_id, status, name, kind, details_status, original_path, thumb_path, created_at, confirmed_at)
     VALUES (?, 'confirmed', ?, 'coat', 'suggested', ?, ?, ?, ?)`
  ).run(id, `Coat of member ${count}`, `photos/${id}/piece${id}.jpg`, `photos/${id}/piece${id}-thumb.webp`, at, at);
  return { id, token, address, folder };
}

function zipEntries(file) {
  return execFileSync('unzip', ['-Z1', file]).toString().trim().split('\n').sort();
}

function zipText(file, entry) {
  return execFileSync('unzip', ['-p', file, entry]).toString();
}

test('Download everything gives a zip of only your own data and photos', async () => {
  const marta = addMember();
  const sara = addMember();

  assert.equal((await request('GET', '/me/export')).status, 401);

  const res = await request('GET', '/me/export', marta.token);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-type'), 'application/zip');
  assert.match(res.headers.get('content-disposition'), /caro-\d{4}-\d{2}-\d{2}\.zip/);

  const file = path.join(dataDir, 'export.zip');
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  assert.deepEqual(zipEntries(file), [
    'caro/README.txt',
    'caro/caro.json',
    `caro/photos/piece${marta.id}-thumb.webp`,
    `caro/photos/piece${marta.id}.jpg`,
  ].sort());

  const data = JSON.parse(zipText(file, 'caro/caro.json'));
  assert.equal(data.account.email, marta.address);
  assert.deepEqual(data.tables.pieces.map((piece) => piece.name), ['Coat of member 1']);
  assert.equal(data.tables.sessions, undefined, 'sessions are left out');
  const text = zipText(file, 'caro/caro.json');
  assert.ok(!text.includes(sara.address) && !text.includes('member 2'), "never another member's data");
});

test('Delete account removes the member, their photos, invitation and codes', async () => {
  const leaving = addMember();
  const staying = addMember();

  assert.equal((await request('DELETE', '/me')).status, 401);
  const res = await request('DELETE', '/me', leaving.token);
  assert.equal(res.status, 200);

  assert.equal(db.prepare('SELECT COUNT(*) FROM users WHERE id = ?').pluck().get(leaving.id), 0);
  assert.equal(db.prepare('SELECT COUNT(*) FROM pieces WHERE user_id = ?').pluck().get(leaving.id), 0);
  assert.equal(db.prepare('SELECT COUNT(*) FROM sessions WHERE user_id = ?').pluck().get(leaving.id), 0);
  assert.equal(db.prepare('SELECT COUNT(*) FROM invitations WHERE email = ?').pluck().get(leaving.address), 0);
  assert.equal(db.prepare('SELECT COUNT(*) FROM login_codes WHERE email = ?').pluck().get(leaving.address), 0);
  assert.equal(fs.existsSync(leaving.folder), false);

  // The old session no longer works, and nobody else was touched.
  assert.equal((await request('GET', '/me', leaving.token)).status, 401);
  assert.equal((await request('GET', '/me', staying.token)).status, 200);
  assert.equal(fs.readdirSync(staying.folder).length, 2);
});

test('the admin cannot delete their own account', async () => {
  const admin = addMember('admin');
  const res = await request('DELETE', '/me', admin.token);
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, 'The admin account cannot be deleted.');
  assert.equal(db.prepare('SELECT COUNT(*) FROM users WHERE id = ?').pluck().get(admin.id), 1);
});

test('emails print on this Mac instead of being sent', async () => {
  const lines = [];
  const log = console.log;
  console.log = (text) => lines.push(text);
  try {
    await email.sendSignInCode('someone@example.test', '123456', 15);
  } finally {
    console.log = log;
  }
  assert.match(lines.join('\n'), /To: someone@example\.test[\s\S]*123456/);
});

test('a backup holds the database and every photo, and the last 3 are kept', async () => {
  const member = addMember();
  const file = await makeBackup();
  const entries = zipEntries(file);
  assert.ok(entries.includes('caro.db'));
  assert.ok(entries.includes(`photos/${member.id}/piece${member.id}.jpg`));

  // The copy is a working database with the member in it.
  execFileSync('unzip', ['-o', file, 'caro.db', '-d', path.join(dataDir, 'restored')]);
  const Database = require('better-sqlite3');
  const restored = new Database(path.join(dataDir, 'restored', 'caro.db'), { readonly: true });
  assert.equal(restored.prepare('SELECT COUNT(*) FROM users WHERE id = ?').pluck().get(member.id), 1);
  restored.close();

  // Older backups beyond the last 3 are deleted.
  for (const day of ['2020-01-01', '2020-01-02', '2020-01-03']) fs.writeFileSync(path.join(backupDir, `caro-${day}.zip`), '');
  await makeBackup();
  assert.equal(backups().length, 3);
  assert.ok(!backups().includes('caro-2020-01-01.zip'));
  assert.ok(!fs.readdirSync(backupDir).some((name) => name.endsWith('.part') || name.endsWith('.db')));
});
