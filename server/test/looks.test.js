// npm test
// Checks looks (PRD sections 6 to 8, ticket T7): locked until the unlock, the styling table,
// saving a built look with its slots, occasions and seasons, numbers never reused, changing and
// deleting, and that a member never reaches another member's looks or pieces. Like the other
// tests, it runs on a throwaway database, with DEV_TODAY in autumn. No AI is called.

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

const db = require('../src/db');
const app = require('../src/app');
const { makeToken, hashToken } = require('../src/lib/auth');
const { now, iso } = require('../src/lib/today');
const setup = require('../src/lib/setup');

const AMSTERDAM = { id: 2759794, high: [6.2, 6.9, 10.1, 14.3, 17.8, 20.3, 22.5, 22.4, 19.2, 14.7, 10.0, 6.9] };
const FOUR = [
  { name: 'Spring', months: [3, 4, 5] },
  { name: 'Summer', months: [6, 7, 8] },
  { name: 'Autumn', months: [9, 10, 11] },
  { name: 'Winter', months: [12, 1, 2] },
];

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

async function call(method, route, { body, token } = {}) {
  const res = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

// A member who finished set-up, signed in, with Caro's four occasions and Amsterdam's four seasons.
let memberCount = 0;
function addMember() {
  memberCount += 1;
  const at = iso(now());
  const id = Number(
    db
      .prepare(`INSERT INTO users (email, name, status, onboarding_step, created_at) VALUES (?, 'Test', 'active', 6, ?)`)
      .run(`looks${memberCount}@example.test`, at).lastInsertRowid
  );
  const token = makeToken();
  db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, hashToken(token), at, at);
  require('../src/lib/occasions').proposeFor(id);
  db.prepare(
    `INSERT INTO cities (id, name, country, latitude, longitude, created_at) VALUES (?, 'Amsterdam', 'NL', 52.37, 0, ?) ON CONFLICT (id) DO NOTHING`
  ).run(AMSTERDAM.id, at);
  const addMonth = db.prepare('INSERT OR REPLACE INTO city_weather (city_id, month, high_c, rain_mm) VALUES (?, ?, ?, 50)');
  AMSTERDAM.high.forEach((high, i) => addMonth.run(AMSTERDAM.id, i + 1, high));
  db.prepare(`UPDATE users SET city_id = ?, city = 'Amsterdam', country = 'NL' WHERE id = ?`).run(AMSTERDAM.id, id);
  setup.saveSeasons(id, FOUR);
  db.prepare('UPDATE users SET unlocked_at = ? WHERE id = ?').run(at, id);
  return { id, token };
}

const byName = (userId, table) =>
  Object.fromEntries(db.prepare(`SELECT name, id FROM ${table} WHERE user_id = ?`).all(userId).map((row) => [row.name, row.id]));

function addPiece(userId, name, kind, status = 'confirmed') {
  return Number(
    db
      .prepare(
        `INSERT INTO pieces (user_id, status, name, kind, details_status, original_path, thumb_path, created_at, confirmed_at)
         VALUES (?, ?, ?, ?, 'suggested', 'photos/none-photo.jpg', 'photos/none-thumb.webp', ?, ?)`
      )
      .run(userId, status, name, kind, iso(now()), iso(now())).lastInsertRowid
  );
}

// The Done when of T7: the camel coat, a shirt, trousers and shoes.
function wardrobeOf(userId) {
  return {
    coat: addPiece(userId, 'Camel wool coat', 'coat'),
    shirt: addPiece(userId, 'White cotton shirt', 'shirt'),
    jumper: addPiece(userId, 'Grey wool jumper', 'jumper'),
    trousers: addPiece(userId, 'Navy wool trousers', 'trousers'),
    dress: addPiece(userId, 'Black midi dress', 'dress'),
    loafers: addPiece(userId, 'Black leather loafers', 'loafers'),
    trainers: addPiece(userId, 'Cream trainers', 'trainers'),
    belt: addPiece(userId, 'Brown belt', 'belt'),
    scarf: addPiece(userId, 'Wool scarf', 'scarf'),
  };
}

test('looks are closed until the wardrobe opens', async () => {
  const { id, token } = addMember();
  db.prepare('UPDATE users SET unlocked_at = NULL WHERE id = ?').run(id);
  const p = wardrobeOf(id);
  assert.equal((await call('GET', '/me/looks', { token })).status, 403);
  assert.equal((await call('GET', '/me/looks/table', { token })).status, 403);
  assert.equal((await call('POST', '/me/looks', { token, body: { pieces: [p.coat, p.shirt] } })).status, 403);
  assert.equal((await call('GET', '/me/looks')).status, 401);
});

test('the styling table has every counted piece with its slot, and the current season', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  addPiece(id, 'Waiting', 'shirt', 'pending');
  const table = (await call('GET', '/me/looks/table', { token })).body;
  assert.equal(table.pieces.length, Object.keys(p).length, 'pieces waiting for review are not on the tray');
  assert.equal(table.pieces.find((x) => x.id === p.dress).slot, 'one-piece');
  assert.equal(table.currentSeason.name, 'Autumn');
  assert.equal(table.occasions.length, 4);
});

test('a built look is saved with its slots, occasions and seasons, and shows on the piece page', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const office = byName(id, 'occasions').Office;
  const autumn = byName(id, 'seasons').Autumn;

  const saved = await call('POST', '/me/looks', {
    token,
    body: { pieces: [p.coat, p.shirt, p.trousers, p.loafers], occasions: [office], seasons: [autumn] },
  });
  assert.equal(saved.status, 201);
  assert.equal(saved.body.look.number, 1);
  assert.equal(saved.body.look.source, 'built');
  assert.deepEqual(saved.body.look.pieces.map((x) => x.slot), ['outer layer', 'top', 'bottom', 'shoes']);
  assert.deepEqual(saved.body.look.occasions, [office]);
  assert.deepEqual(saved.body.look.seasons, [autumn]);

  const list = (await call('GET', '/me/looks', { token })).body;
  assert.deepEqual(list.looks.map((l) => l.number), [1]);

  const coat = (await call('GET', `/me/pieces/${p.coat}`, { token })).body;
  assert.equal(coat.piece.looks, 1);
  assert.deepEqual(coat.looks.map((l) => [l.number, l.occasions]), [[1, ['Office']]]);
});

test('one piece per slot, several accessories, and a dress takes the bottom\'s place', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const post = (pieces) => call('POST', '/me/looks', { token, body: { pieces } });

  assert.equal((await post([p.coat])).body.error, 'A look needs at least two pieces.');
  assert.equal((await post([p.shirt, p.jumper])).body.error, 'One top per look.');
  assert.equal((await post([p.loafers, p.trainers])).body.error, 'One pair of shoes per look.');
  assert.equal((await post([p.dress, p.trousers])).status, 400);
  assert.equal((await post([p.jumper, p.dress, p.loafers, p.belt, p.scarf])).status, 201, 'a top over a dress, and two accessories');
  assert.equal((await post([p.coat, 999999])).status, 400);
});

test('numbers are never reused, and a look can be changed and deleted', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const one = (await call('POST', '/me/looks', { token, body: { pieces: [p.coat, p.shirt] } })).body.look;
  const two = (await call('POST', '/me/looks', { token, body: { pieces: [p.dress, p.loafers] } })).body.look;
  assert.equal(two.number, 2);

  const changed = await call('PUT', `/me/looks/${one.id}`, { token, body: { pieces: [p.coat, p.jumper, p.trousers], occasions: [byName(id, 'occasions')['Day out']] } });
  assert.equal(changed.status, 200);
  assert.equal(changed.body.look.number, 1);
  assert.deepEqual(changed.body.look.pieces.map((x) => x.id), [p.coat, p.jumper, p.trousers]);

  assert.equal((await call('DELETE', `/me/looks/${two.id}`, { token })).status, 200);
  assert.equal((await call('GET', `/me/looks/${two.id}`, { token })).status, 404);
  const three = (await call('POST', '/me/looks', { token, body: { pieces: [p.dress, p.trainers] } })).body.look;
  assert.equal(three.number, 3, 'No. 2 is not given again');
  assert.ok(db.prepare('SELECT 1 FROM pieces WHERE id = ?').get(p.dress), 'deleting a look keeps its pieces');
});

test('removing a piece takes it off its looks, and a look left empty goes', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const look = (await call('POST', '/me/looks', { token, body: { pieces: [p.shirt, p.trousers] } })).body.look;
  await call('DELETE', `/me/pieces/${p.shirt}`, { token });
  assert.deepEqual((await call('GET', `/me/looks/${look.id}`, { token })).body.look.pieces.map((x) => x.id), [p.trousers]);
  await call('DELETE', `/me/pieces/${p.trousers}`, { token });
  assert.equal((await call('GET', `/me/looks/${look.id}`, { token })).status, 404);
});

test("a member never reaches another member's looks or pieces", async () => {
  const marta = addMember();
  const sara = addMember();
  const mp = wardrobeOf(marta.id);
  const sp = wardrobeOf(sara.id);
  const look = (await call('POST', '/me/looks', { token: marta.token, body: { pieces: [mp.coat, mp.shirt] } })).body.look;

  assert.equal((await call('GET', `/me/looks/${look.id}`, { token: sara.token })).status, 404);
  assert.equal((await call('PUT', `/me/looks/${look.id}`, { token: sara.token, body: { pieces: [sp.coat, sp.shirt] } })).status, 404);
  assert.equal((await call('DELETE', `/me/looks/${look.id}`, { token: sara.token })).status, 404);
  assert.deepEqual((await call('GET', '/me/looks', { token: sara.token })).body.looks, []);
  assert.equal((await call('POST', '/me/looks', { token: sara.token, body: { pieces: [sp.coat, mp.shirt] } })).status, 400);
  const martaOffice = byName(marta.id, 'occasions').Office;
  assert.equal((await call('POST', '/me/looks', { token: sara.token, body: { pieces: [sp.coat, sp.shirt], occasions: [martaOffice] } })).status, 400);
});
