// npm test
// Checks the wardrobe (PRD sections 5, 8, 11 and 14): piece photos, their details, the review
// queue and the unlock rule. Like the other tests, it runs on a throwaway database and photo
// folder, and Claude is replaced by a fake, so it costs nothing and needs no network.

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

// Must be set before the database and today.js are loaded.
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caro-test-'));
process.env.DATA_DIR = dataDir;
process.env.DEV_TODAY = '2026-10-30';
delete process.env.NODE_ENV;

const sharp = require('sharp');
const db = require('../src/db');
const app = require('../src/app');
const { makeToken, hashToken } = require('../src/lib/auth');
const { cleanUp } = require('../src/jobs/clean-up');
const { now, iso, DAY } = require('../src/lib/today');

let server;
let base;

before(async () => {
  server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://localhost:${server.address().port}`;
});

after(() => {
  server.close();
  db.close();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

// Helpers

async function call(method, route, { body, token } = {}) {
  const res = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const type = res.headers.get('content-type') || '';
  return {
    status: res.status,
    headers: res.headers,
    body: type.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer()),
  };
}

// A member who finished set-up (step 6), signed in, with Caro's four occasions.
let memberCount = 0;
function addMember(name = 'Test') {
  memberCount += 1;
  const at = iso(now());
  const { lastInsertRowid: id } = db
    .prepare(`INSERT INTO users (email, name, status, onboarding_step, created_at) VALUES (?, ?, 'active', 6, ?)`)
    .run(`member${memberCount}@example.test`, name, at);
  const token = makeToken();
  db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, hashToken(token), at, at);
  require('../src/lib/occasions').proposeFor(id);
  return { id: Number(id), token };
}

// A photo as the iPhone sends it: a JPEG with the camera and the place it was taken in its EXIF.
async function photoWithLocation(width = 3000, height = 2000) {
  const bytes = await sharp({ create: { width, height, channels: 3, background: '#B4765F' } })
    .jpeg()
    .withExif({
      IFD0: { Make: 'Apple', Model: 'iPhone 14 Pro' },
      IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '51/1 55/1 21/1', GPSLongitudeRef: 'E', GPSLongitude: '4/1 28/1 45/1' },
    })
    .toBuffer();
  return bytes.toString('base64');
}

// A cut-out: the piece on a transparent background.
async function cutOut() {
  const bytes = await sharp({ create: { width: 800, height: 1200, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: { create: { width: 400, height: 900, channels: 4, background: '#2E3A55' } }, top: 150, left: 200 }])
    .png()
    .toBuffer();
  return bytes.toString('base64');
}

function file(relative) {
  return path.join(dataDir, relative);
}

function pieceRow(id) {
  return db.prepare('SELECT * FROM pieces WHERE id = ?').get(id);
}

async function addPiece(token, { withCutout = true } = {}) {
  const added = await call('POST', '/me/pieces', {
    token,
    body: { photo: await photoWithLocation(), cutout: withCutout ? await cutOut() : null },
  });
  assert.equal(added.status, 201, added.body.error);
  return added.body.piece;
}

// Photos

test('a new piece keeps its photo, cut-out and thumbnail, and waits for review', async () => {
  const { token } = addMember();
  const piece = await addPiece(token);

  assert.equal(piece.status, 'pending');
  assert.ok(piece.images.photo.startsWith(`/me/pieces/${piece.id}/photo?v=`));
  assert.ok(piece.images.cutout);
  assert.ok(piece.images.thumb);

  const row = pieceRow(piece.id);
  const photo = await sharp(file(row.original_path)).metadata();
  assert.equal(photo.format, 'jpeg');
  assert.equal(Math.max(photo.width, photo.height), 2000, 'resized to 2000 on the long side');

  const cutout = await sharp(file(row.cutout_path)).metadata();
  assert.equal(cutout.format, 'webp');
  assert.equal(cutout.hasAlpha, true, 'the cut-out keeps its transparent background');

  const thumb = await sharp(file(row.thumb_path)).metadata();
  assert.equal(Math.max(thumb.width, thumb.height), 600);
  assert.equal(thumb.hasAlpha, true, 'the thumbnail is made from the cut-out');
});

test('no location data or other EXIF is stored', async () => {
  const { token } = addMember();
  const piece = await addPiece(token);
  const row = pieceRow(piece.id);
  for (const stored of [row.original_path, row.cutout_path, row.thumb_path]) {
    const metadata = await sharp(file(stored)).metadata();
    assert.equal(metadata.exif, undefined, `${stored} has no EXIF`);
  }
  assert.ok(!fs.readFileSync(file(row.original_path)).toString('latin1').includes('iPhone'));
});

test('when nothing lifted, the piece keeps its photo, and the thumbnail is made from it', async () => {
  const { token } = addMember();
  const piece = await addPiece(token, { withCutout: false });
  assert.equal(piece.images.cutout, null);
  const row = pieceRow(piece.id);
  assert.equal(row.cutout_path, null);
  assert.equal((await sharp(file(row.thumb_path)).metadata()).hasAlpha, false);
});

test('a missing photo or a file that is not a picture is refused, and nothing is kept', async () => {
  const { id, token } = addMember();
  assert.equal((await call('POST', '/me/pieces', { token, body: {} })).status, 400);
  const notAPicture = await call('POST', '/me/pieces', { token, body: { photo: Buffer.from('hello').toString('base64') } });
  assert.equal(notAPicture.status, 400);
  assert.equal(notAPicture.body.error, 'Caro could not read this photo. Try another one.');
  assert.equal(db.prepare('SELECT COUNT(*) FROM pieces WHERE user_id = ?').pluck().get(id), 0);
  assert.deepEqual(fs.readdirSync(file(`photos/${id}`)), []);
});

test('photos are served only to their owner, through signed-in requests', async () => {
  const owner = addMember('Owner');
  const other = addMember('Other');
  const piece = await addPiece(owner.token);

  const mine = await call('GET', piece.images.thumb, { token: owner.token });
  assert.equal(mine.status, 200);
  assert.equal(mine.headers.get('content-type'), 'image/webp');
  assert.ok(mine.headers.get('cache-control').startsWith('private'));
  assert.equal((await call('GET', piece.images.photo, { token: owner.token })).headers.get('content-type'), 'image/jpeg');

  assert.equal((await call('GET', piece.images.photo, { token: other.token })).status, 404, 'another member');
  assert.equal((await call('GET', piece.images.photo)).status, 401, 'signed out');
  assert.equal((await call('GET', `/me/pieces/${piece.id}/secret`, { token: owner.token })).status, 404);
});

test('removing a piece deletes its photos; another member cannot remove it', async () => {
  const owner = addMember('Owner');
  const other = addMember('Other');
  const piece = await addPiece(owner.token);
  const row = pieceRow(piece.id);

  assert.equal((await call('DELETE', `/me/pieces/${piece.id}`, { token: other.token })).status, 404);
  assert.ok(fs.existsSync(file(row.original_path)));

  assert.equal((await call('DELETE', `/me/pieces/${piece.id}`, { token: owner.token })).status, 200);
  assert.equal(pieceRow(piece.id), undefined);
  for (const stored of [row.original_path, row.cutout_path, row.thumb_path]) {
    assert.ok(!fs.existsSync(file(stored)), `${stored} deleted`);
  }
});

test('the daily clean-up deletes the photos of a member removed more than 30 days ago', async () => {
  const removed = addMember('Removed');
  await addPiece(removed.token);
  assert.ok(fs.existsSync(file(`photos/${removed.id}`)));

  db.prepare(`UPDATE users SET status = 'removed', removed_at = ? WHERE id = ?`).run(iso(now()), removed.id);
  cleanUp(new Date(now().getTime() + 31 * DAY));

  assert.equal(db.prepare('SELECT 1 FROM users WHERE id = ?').get(removed.id), undefined);
  assert.ok(!fs.existsSync(file(`photos/${removed.id}`)));
});
