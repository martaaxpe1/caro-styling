// npm test
// Checks sign in and the admin area against the rules in PRD sections 4 and 11, using
// Node's own test runner. It runs on a throwaway database in a temporary folder, so your
// data/caro.db is never touched. Emails are caught here instead of printed.

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

// Must be set before the database is opened.
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caro-test-'));
process.env.DATA_DIR = dataDir;

const db = require('../src/db');
const app = require('../src/app');
const email = require('../src/lib/email');
const { cleanUp } = require('../src/jobs/clean-up');
const { now, iso, DAY, HOUR } = require('../src/lib/today');

// The last code and invitation "sent" to each email.
const codes = {};
const invitations = {};
email.sendSignInCode = (to, code) => {
  codes[to] = code;
};
email.sendInvitation = (invitation) => {
  invitations[invitation.email] = invitation;
};

const ADMIN = 'admin@example.test';
let server;
let base;
let adminToken;

before(async () => {
  db.prepare(
    `INSERT INTO users (email, name, role, status, onboarding_step, city, country, created_at)
     VALUES (?, 'Marta', 'admin', 'active', 6, 'Rotterdam', 'NL', ?)`
  ).run(ADMIN, iso(now()));

  server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://localhost:${server.address().port}`;
});

after(() => {
  server.close();
  db.close();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

async function call(method, route, { body, token } = {}) {
  const res = await fetch(base + route, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

function askCode(address) {
  return call('POST', '/auth/code', { body: { email: address } });
}

function verify(address, code) {
  return call('POST', '/auth/verify', { body: { email: address, code } });
}

async function signIn(address) {
  const asked = await askCode(address);
  assert.equal(asked.status, 200, asked.body.error);
  const verified = await verify(address, codes[address]);
  assert.equal(verified.status, 200, verified.body.error);
  return verified.body;
}

function userByEmail(address) {
  return db.prepare('SELECT * FROM users WHERE email = ?').get(address);
}

test('the admin signs in with a code and stays signed in with the token', async () => {
  const { token, member } = await signIn(ADMIN);
  assert.equal(member.role, 'admin');
  adminToken = token;

  const me = await call('GET', '/me', { token });
  assert.equal(me.status, 200);
  assert.equal(me.body.member.email, ADMIN);
});

test('only hashes are stored, never the code or the token', () => {
  const code = db.prepare('SELECT code_hash FROM login_codes WHERE email = ? ORDER BY id DESC').pluck().get(ADMIN);
  assert.ok(!code.includes(codes[ADMIN]));
  assert.equal(db.prepare('SELECT COUNT(*) FROM sessions WHERE token_hash = ?').pluck().get(adminToken), 0);
});

test('an email with no invitation is refused', async () => {
  const asked = await askCode('nobody@example.test');
  assert.equal(asked.status, 403);
  assert.equal(asked.body.error, 'This email does not have access to Caro.');
});

test('a wrong code counts, and after 5 wrong tries even the right code is refused', async () => {
  await askCode(ADMIN);
  for (let left = 4; left >= 0; left--) {
    const wrong = await verify(ADMIN, codes[ADMIN] === '000000' ? '111111' : '000000');
    assert.equal(wrong.status, 400);
  }
  const right = await verify(ADMIN, codes[ADMIN]);
  assert.equal(right.status, 400);
  assert.equal(right.body.error, 'Too many tries. Send a new code.');
});

test('a code stops working after 15 minutes', async () => {
  await askCode(ADMIN);
  db.prepare('UPDATE login_codes SET expires_at = ? WHERE email = ? AND used_at IS NULL').run(iso(now()), ADMIN);
  const late = await verify(ADMIN, codes[ADMIN]);
  assert.equal(late.status, 400);
  assert.equal(late.body.error, 'This code has expired. Send a new one.');
});

test('at most 5 codes per email per hour', async () => {
  // The admin already asked for 3 codes above.
  await askCode(ADMIN);
  await askCode(ADMIN);
  const sixth = await askCode(ADMIN);
  assert.equal(sixth.status, 429);
  db.prepare('DELETE FROM login_codes WHERE email = ?').run(ADMIN);
});

test('with DEV_TODAY, codes from other real days do not count towards the hour', async () => {
  // DEV_TODAY keeps the date, so yesterday evening's codes look like later today.
  const later = iso(new Date(now().getTime() + 3 * HOUR));
  const add = db.prepare(`INSERT INTO login_codes (email, code_hash, created_at, expires_at, used_at) VALUES (?, 'x', ?, ?, ?)`);
  for (let i = 0; i < 5; i++) add.run(ADMIN, later, later, later);
  const asked = await askCode(ADMIN);
  assert.equal(asked.status, 200, asked.body.error);
  db.prepare('DELETE FROM login_codes WHERE email = ?').run(ADMIN);
});

test('the admin adds a person, who signs in and lands in onboarding', async () => {
  const added = await call('POST', '/admin/invitations', { token: adminToken, body: { name: 'Test', email: ' Test@Example.test ' } });
  assert.equal(added.status, 201, added.body.error);
  assert.equal(added.body.invitation.email, 'test@example.test');
  assert.ok(invitations['test@example.test']);

  const { member } = await signIn('test@example.test');
  assert.equal(member.name, 'Test');
  assert.equal(member.role, 'member');
  assert.equal(member.status, 'onboarding');
  assert.equal(member.onboardingStep, 1);

  const admin = await call('GET', '/admin', { token: adminToken });
  assert.equal(admin.body.invitations.length, 0, 'an accepted invitation is no longer listed');
  assert.deepEqual(
    admin.body.members.map((m) => m.email),
    [ADMIN, 'test@example.test']
  );
});

test('the same email cannot be invited twice', async () => {
  const member = await call('POST', '/admin/invitations', { token: adminToken, body: { name: 'Test', email: 'test@example.test' } });
  assert.equal(member.status, 409);

  await call('POST', '/admin/invitations', { token: adminToken, body: { name: 'Ana', email: 'ana@example.test' } });
  const again = await call('POST', '/admin/invitations', { token: adminToken, body: { name: 'Ana', email: 'ana@example.test' } });
  assert.equal(again.status, 409);
});

test('admin routes are checked on the server', async () => {
  const { token } = await signIn('test@example.test');
  const asMember = await call('GET', '/admin', { token });
  assert.equal(asMember.status, 403);
  const addAsMember = await call('POST', '/admin/invitations', { token, body: { name: 'X', email: 'x@example.test' } });
  assert.equal(addAsMember.status, 403);
  const signedOut = await call('GET', '/admin');
  assert.equal(signedOut.status, 401);
});

test('resend restarts the 14 days, and a cancelled invitation cannot sign in', async () => {
  const { body } = await call('GET', '/admin', { token: adminToken });
  const ana = body.invitations.find((i) => i.email === 'ana@example.test');

  db.prepare('UPDATE invitations SET expires_at = ? WHERE id = ?').run(iso(new Date(now().getTime() + DAY)), ana.id);
  const resent = await call('POST', `/admin/invitations/${ana.id}/resend`, { token: adminToken });
  assert.equal(resent.status, 200);
  const daysLeft = (new Date(resent.body.invitation.expiresAt) - now()) / DAY;
  assert.ok(daysLeft > 13.9 && daysLeft <= 14);

  const cancelled = await call('POST', `/admin/invitations/${ana.id}/cancel`, { token: adminToken });
  assert.equal(cancelled.status, 200);
  assert.equal((await askCode('ana@example.test')).status, 403);
});

test('an invitation cancelled after the code was sent cannot sign in', async () => {
  await call('POST', '/admin/invitations', { token: adminToken, body: { name: 'Bo', email: 'bo@example.test' } });
  await askCode('bo@example.test');
  db.prepare(`UPDATE invitations SET status = 'cancelled' WHERE email = ?`).run('bo@example.test');
  const verified = await verify('bo@example.test', codes['bo@example.test']);
  assert.equal(verified.status, 403);
  assert.equal(userByEmail('bo@example.test'), undefined);
});

test('a removed person is signed out and cannot sign in; restoring works', async () => {
  const { token } = await signIn('test@example.test');
  const id = userByEmail('test@example.test').id;

  const removed = await call('POST', `/admin/members/${id}/remove`, { token: adminToken });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.member.status, 'removed');
  assert.ok(removed.body.member.deletedOn);

  assert.equal((await call('GET', '/me', { token })).status, 401, 'their session ended');
  assert.equal((await askCode('test@example.test')).status, 403);

  const restored = await call('POST', `/admin/members/${id}/restore`, { token: adminToken });
  assert.equal(restored.status, 200);
  assert.equal(restored.body.member.status, 'onboarding');

  const { member } = await signIn('test@example.test');
  assert.equal(member.status, 'onboarding');
});

test("the admin's access cannot be removed", async () => {
  const id = userByEmail(ADMIN).id;
  const removed = await call('POST', `/admin/members/${id}/remove`, { token: adminToken });
  assert.equal(removed.status, 400);
});

test('the clean-up expires old invitations and deletes members removed 30 days ago', async () => {
  const id = userByEmail('test@example.test').id;
  db.prepare(
    `INSERT INTO stores (user_id, name, sells_online, position, created_at) VALUES (?, 'COS', 1, 1, ?)`
  ).run(id, iso(now()));
  await call('POST', `/admin/members/${id}/remove`, { token: adminToken });
  await call('POST', '/admin/invitations', { token: adminToken, body: { name: 'Cy', email: 'cy@example.test' } });

  // 29 days on: nothing of Test is deleted yet.
  cleanUp(new Date(now().getTime() + 29 * DAY));
  assert.ok(userByEmail('test@example.test'));

  // 31 days on: Test and everything Test had is gone; Cy's invitation has expired.
  const result = cleanUp(new Date(now().getTime() + 31 * DAY));
  assert.equal(result.membersDeleted, 1);
  assert.equal(userByEmail('test@example.test'), undefined);
  assert.equal(db.prepare('SELECT COUNT(*) FROM stores WHERE user_id = ?').pluck().get(id), 0);
  assert.equal(db.prepare('SELECT COUNT(*) FROM invitations WHERE email = ?').pluck().get('test@example.test'), 0);
  assert.equal(db.prepare('SELECT status FROM invitations WHERE email = ?').pluck().get('cy@example.test'), 'expired');
});

test('signing out ends the session', async () => {
  const out = await call('POST', '/auth/sign-out', { token: adminToken });
  assert.equal(out.status, 200);
  assert.equal((await call('GET', '/me', { token: adminToken })).status, 401);
});
