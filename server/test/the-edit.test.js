// npm test
// Checks the edit (PRD sections 7, 8 and 9, ticket T6): the contents with the current season and
// "not styled yet", a chapter with what its filters need, the piece page with the looks it is in,
// maybe, brand and notes, the overview, and the one-batch check of new seasons. Like the other
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
const TWO = [
  { name: 'Warm', months: [4, 5, 6, 7, 8, 9] },
  { name: 'Cool', months: [10, 11, 12, 1, 2, 3] },
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
      .run(`edit${memberCount}@example.test`, at).lastInsertRowid
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
  return { id, token };
}

const byName = (userId, table) =>
  Object.fromEntries(db.prepare(`SELECT name, id FROM ${table} WHERE user_id = ?`).all(userId).map((row) => [row.name, row.id]));

// A counted piece put straight into the database, with its colours, seasons and occasions by name.
function addPiece(userId, { name, kind, colours = [], warmth = null, seasons = [], occasions = [], status = 'confirmed' }) {
  const id = Number(
    db
      .prepare(
        `INSERT INTO pieces (user_id, status, name, kind, warmth, details_status, original_path, thumb_path, created_at, confirmed_at)
         VALUES (?, ?, ?, ?, ?, 'suggested', 'photos/none-photo.jpg', 'photos/none-thumb.webp', ?, ?)`
      )
      .run(userId, status, name, kind, warmth, iso(now()), iso(now())).lastInsertRowid
  );
  colours.forEach((colour, i) => db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, ?)').run(userId, id, colour, i + 1));
  const seasonIds = byName(userId, 'seasons');
  seasons.forEach((s) => db.prepare('INSERT INTO piece_seasons (user_id, piece_id, season_id) VALUES (?, ?, ?)').run(userId, id, seasonIds[s]));
  const occasionIds = byName(userId, 'occasions');
  occasions.forEach((o) => db.prepare('INSERT INTO piece_occasions (user_id, piece_id, occasion_id) VALUES (?, ?, ?)').run(userId, id, occasionIds[o]));
  return id;
}

// A look, made by hand: looks themselves come in T7.
function addLook(userId, number, pieces, occasions = []) {
  const id = Number(
    db.prepare(`INSERT INTO looks (user_id, number, source, created_at) VALUES (?, ?, 'built', ?)`).run(userId, number, iso(now())).lastInsertRowid
  );
  pieces.forEach(([pieceId, slot]) => db.prepare('INSERT INTO look_pieces (user_id, look_id, piece_id, slot) VALUES (?, ?, ?, ?)').run(userId, id, pieceId, slot));
  const occasionIds = byName(userId, 'occasions');
  occasions.forEach((o) => db.prepare('INSERT INTO look_occasions (user_id, look_id, occasion_id) VALUES (?, ?, ?)').run(userId, id, occasionIds[o]));
  return id;
}

function wardrobe(token) {
  return call('GET', '/me/wardrobe', { token }).then((r) => r.body);
}

test('the edit names the current season, and "not styled yet" waits for the first look', async () => {
  const { id, token } = addMember();
  const coat = addPiece(id, { name: 'Camel wool coat', kind: 'coat' });
  addPiece(id, { name: 'Brown blazer', kind: 'blazer' });
  const shirt = addPiece(id, { name: 'White shirt', kind: 'shirt' });

  let edit = await wardrobe(token);
  assert.deepEqual(edit.currentSeason?.name, 'Autumn', 'DEV_TODAY is 30 October');
  assert.equal(edit.looks, 0);
  assert.deepEqual(edit.chapters.map((c) => [c.name, c.count, c.notStyled]), [['outerwear', 2, null], ['tops', 1, null]]);

  addLook(id, 1, [[coat, 'outer layer'], [shirt, 'top']]);
  edit = await wardrobe(token);
  assert.equal(edit.looks, 1);
  assert.deepEqual(edit.chapters.map((c) => [c.name, c.count, c.notStyled]), [['outerwear', 2, 1], ['tops', 1, 0]]);
});

test('with no seasons there is no current season', async () => {
  const { id, token } = addMember();
  setup.clearSeasons(id);
  assert.equal((await wardrobe(token)).currentSeason, null);
});

test('a chapter sends its pieces with what the filters need', async () => {
  const { id, token } = addMember();
  addPiece(id, { name: 'Grey jumper', kind: 'jumper', colours: ['grey'], seasons: ['Autumn', 'Winter'], occasions: ['Office'] });
  addPiece(id, { name: 'Cream vest', kind: 'knitted vest', colours: ['cream', 'navy'], seasons: ['Spring'], status: 'maybe' });
  addPiece(id, { name: 'Waiting cardigan', kind: 'cardigan', status: 'pending' });

  const chapter = (await call('GET', '/me/pieces?chapter=knitwear', { token })).body;
  assert.deepEqual(chapter.pieces.map((p) => [p.name, p.status, p.colours]), [
    ['Cream vest', 'maybe', ['cream', 'navy']],
    ['Grey jumper', 'confirmed', ['grey']],
  ]);
  assert.deepEqual(chapter.seasons.map((s) => s.name), ['Spring', 'Summer', 'Autumn', 'Winter']);
  assert.deepEqual(chapter.occasions.map((o) => o.name), ['Office', 'Working from home', 'Night out', 'Day out']);
  assert.equal(chapter.currentSeason.name, 'Autumn');
  const autumn = chapter.currentSeason.id;
  assert.deepEqual(chapter.pieces.filter((p) => p.seasons.includes(autumn)).map((p) => p.name), ['Grey jumper']);
});

test('the piece page shows the piece, its looks, and nothing of another member', async () => {
  const { id, token } = addMember();
  const other = addMember();
  const coat = addPiece(id, { name: 'Camel wool coat', kind: 'coat', occasions: ['Office'] });
  const trousers = addPiece(id, { name: 'Navy trousers', kind: 'trousers' });

  let page = (await call('GET', `/me/pieces/${coat}`, { token })).body;
  assert.equal(page.piece.name, 'Camel wool coat');
  assert.equal(page.piece.looks, 0);
  assert.deepEqual(page.looks, []);
  assert.deepEqual(page.occasions.map((o) => o.name).slice(0, 1), ['Office']);

  addLook(id, 1, [[coat, 'outer layer'], [trousers, 'bottom']], ['Office']);
  addLook(id, 2, [[coat, 'outer layer']], ['Day out']);
  page = (await call('GET', `/me/pieces/${coat}`, { token })).body;
  assert.equal(page.piece.looks, 2);
  assert.deepEqual(page.looks.map((l) => [l.number, l.occasions, l.pieces.length]), [[2, ['Day out'], 1], [1, ['Office'], 2]]);

  assert.equal((await call('GET', `/me/pieces/${coat}`, { token: other.token })).status, 404);
  assert.equal((await call('PUT', `/me/pieces/${coat}/status`, { token: other.token, body: { status: 'maybe' } })).status, 404);
});

test('a piece in the edit can be marked maybe and back; a waiting piece cannot', async () => {
  const { id, token } = addMember();
  const coat = addPiece(id, { name: 'Camel wool coat', kind: 'coat' });
  const waiting = addPiece(id, { name: 'Waiting coat', kind: 'coat', status: 'pending' });

  let res = await call('PUT', `/me/pieces/${coat}/status`, { token, body: { status: 'maybe' } });
  assert.equal(res.body.piece.status, 'maybe');
  assert.equal((await wardrobe(token)).progress.pieces, 1, 'a maybe still counts');
  res = await call('PUT', `/me/pieces/${coat}/status`, { token, body: { status: 'confirmed' } });
  assert.equal(res.body.piece.status, 'confirmed');

  assert.equal((await call('PUT', `/me/pieces/${coat}/status`, { token, body: { status: 'pending' } })).status, 400);
  assert.equal((await call('PUT', `/me/pieces/${waiting}/status`, { token, body: { status: 'maybe' } })).status, 400);
});

test('editing a piece changes its name, occasions, brand and notes; left out, brand and notes stay', async () => {
  const { id, token } = addMember();
  const coat = addPiece(id, { name: 'Camel coat', kind: 'coat', occasions: ['Office'] });
  const occasions = byName(id, 'occasions');
  const body = {
    name: 'camel wool coat', kind: 'coat', colours: ['camel'], pattern: 'plain', material: 'wool', warmth: 'warm',
    formality: 'smart', seasons: [], occasions: [occasions.Office, occasions['Day out']], status: 'confirmed',
    brand: '  Arket ', notes: 'From the sale in Rotterdam.',
  };

  let saved = (await call('PUT', `/me/pieces/${coat}`, { token, body })).body.piece;
  assert.equal(saved.name, 'Camel wool coat');
  assert.equal(saved.brand, 'Arket');
  assert.equal(saved.notes, 'From the sale in Rotterdam.');
  assert.deepEqual(saved.occasions, [occasions.Office, occasions['Day out']]);

  const { brand, notes, ...withoutThem } = body;
  saved = (await call('PUT', `/me/pieces/${coat}`, { token, body: withoutThem })).body.piece;
  assert.equal(saved.brand, 'Arket', 'left out: unchanged');
  saved = (await call('PUT', `/me/pieces/${coat}`, { token, body: { ...body, brand: '', notes: null } })).body.piece;
  assert.equal(saved.brand, null, 'empty: cleared');
  assert.equal(saved.notes, null);

  const tooLong = await call('PUT', `/me/pieces/${coat}`, { token, body: { ...body, notes: 'x'.repeat(281) } });
  assert.equal(tooLong.status, 400);
});

test('the overview counts by chapter, main colour, season and occasion; looks facts wait for a look', async () => {
  const { id, token } = addMember();
  const coat = addPiece(id, { name: 'Camel coat', kind: 'coat', colours: ['camel'], seasons: ['Autumn', 'Winter'], occasions: ['Office'] });
  addPiece(id, { name: 'Striped top', kind: 'long-sleeved top', colours: ['navy', 'white'], seasons: ['Autumn'], occasions: ['Office', 'Day out'] });
  addPiece(id, { name: 'Black jeans', kind: 'jeans', colours: ['black'], status: 'maybe' });
  addPiece(id, { name: 'Waiting', kind: 'jeans', colours: ['black'], status: 'pending' });

  let overview = (await call('GET', '/me/wardrobe/overview', { token })).body;
  assert.equal(overview.pieces, 3);
  assert.equal(overview.chapters.length, 7, 'every chapter, empty ones too');
  assert.deepEqual(overview.chapters.filter((c) => c.count).map((c) => [c.name, c.count]), [['outerwear', 1], ['tops', 1], ['trousers', 1]]);
  assert.deepEqual(overview.colours, [{ name: 'black', count: 1 }, { name: 'camel', count: 1 }, { name: 'navy', count: 1 }]);
  assert.deepEqual(overview.seasons.map((s) => [s.name, s.count]), [['Spring', 0], ['Summer', 0], ['Autumn', 2], ['Winter', 1]]);
  assert.equal(overview.noSeason, 1);
  assert.deepEqual(overview.occasions.map((o) => [o.name, o.count]), [['Office', 2], ['Working from home', 0], ['Night out', 0], ['Day out', 1]]);
  assert.equal(overview.noOccasion, 1);
  assert.equal(overview.notInALook, null);
  assert.equal(overview.occasionsFewLooks, null);

  addLook(id, 1, [[coat, 'outer layer']], ['Office']);
  overview = (await call('GET', '/me/wardrobe/overview', { token })).body;
  assert.equal(overview.notInALook.count, 2);
  assert.deepEqual(overview.occasionsFewLooks.map((o) => [o.name, o.looks]), [['Office', 1], ['Working from home', 0], ['Night out', 0], ['Day out', 0]]);

  // Another member's wardrobe is not counted.
  const other = addMember();
  assert.equal((await call('GET', '/me/wardrobe/overview', { token: other.token })).body.pieces, 0);
});

test('after changing the number of seasons, new seasons are checked in one batch by warmth', async () => {
  const { id, token } = addMember();
  const shirt = addPiece(id, { name: 'Linen shirt', kind: 'shirt', warmth: 'light', seasons: ['Spring', 'Summer'] });
  const coat = addPiece(id, { name: 'Wool coat', kind: 'coat', warmth: 'warm', seasons: ['Autumn', 'Winter'] });
  const bag = addPiece(id, { name: 'Bag', kind: 'bag' });
  addPiece(id, { name: 'Waiting', kind: 'shirt', warmth: 'light', status: 'pending' });
  assert.equal((await wardrobe(token)).seasonsToCheck, 0);

  setup.saveSeasons(id, TWO);
  const seasons = byName(id, 'seasons');
  assert.equal((await wardrobe(token)).seasonsToCheck, 3, 'the pieces in the edit, not the one waiting');

  const check = (await call('GET', '/me/wardrobe/seasons-to-check', { token })).body;
  assert.deepEqual(check.seasons.map((s) => s.name), ['Warm', 'Cool']);
  assert.deepEqual(check.groups.map((g) => [g.warmth, g.pieces.map((p) => p.name)]), [
    ['light', ['Linen shirt']],
    ['warm', ['Wool coat']],
    ['none', ['Bag']],
  ]);
  assert.deepEqual(check.groups.find((g) => g.warmth === 'warm').seasons, [seasons.Cool]);

  // Another member's season is refused.
  const other = addMember();
  const foreign = db.prepare('SELECT id FROM seasons WHERE user_id = ? LIMIT 1').pluck().get(other.id);
  assert.equal((await call('POST', '/me/wardrobe/seasons-to-check', { token, body: { light: [foreign] } })).status, 400);

  // Confirm light and none; warm is left out, so the coat is still to check.
  const confirm = await call('POST', '/me/wardrobe/seasons-to-check', {
    token,
    body: { light: [seasons.Warm, seasons.Cool], none: [seasons.Warm] },
  });
  assert.equal(confirm.body.confirmed, 2);
  assert.equal(confirm.body.wardrobe.seasonsToCheck, 1);
  const seasonsOf = (pieceId) => db.prepare('SELECT season_id FROM piece_seasons WHERE piece_id = ? ORDER BY season_id').pluck().all(pieceId);
  assert.deepEqual(seasonsOf(shirt), [seasons.Warm, seasons.Cool].sort((a, b) => a - b));
  assert.deepEqual(seasonsOf(bag), [seasons.Warm]);

  // Saving the coat on its own clears its mark too.
  const body = { name: 'Wool coat', kind: 'coat', colours: [], warmth: 'warm', seasons: [seasons.Cool], occasions: [], status: 'confirmed' };
  await call('PUT', `/me/pieces/${coat}`, { token, body });
  assert.equal((await wardrobe(token)).seasonsToCheck, 0);
});
