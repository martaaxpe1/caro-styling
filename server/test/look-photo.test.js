// npm test
// Checks looks from a photo (PRD sections 7 and 8, ticket T9): spotting only the member's own
// pieces, low certainty asked about, saving a look with its photo, the same look rule, photos
// on a look, and that their files go with the look. Claude is replaced by a stand-in, so no AI
// is called. Like the other tests, it runs on a throwaway database and photo folder.

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const sharp = require('sharp');

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
const lookPhoto = require('../src/lib/look-photo');

// The stand-in for Claude: answers with whatever the test sets in `nextAnswer`, by the piece
// numbers it was given, and keeps the prompt so the test can look at it.
let nextAnswer = () => ({ worn: [], not_in_wardrobe: [], photo_quality: 'clear' });
let lastPrompt = null;
lookPhoto.remote.claude = async ({ prompt, schema }) => {
  lastPrompt = { prompt, schema };
  return nextAnswer(schema.properties.worn.items.properties.piece.enum);
};

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
      .run(`photo${memberCount}@example.test`, at).lastInsertRowid
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

function addPiece(userId, name, kind) {
  return Number(
    db
      .prepare(
        `INSERT INTO pieces (user_id, status, name, kind, details_status, original_path, thumb_path, created_at, confirmed_at)
         VALUES (?, 'confirmed', ?, ?, 'suggested', 'photos/none-photo.jpg', 'photos/none-thumb.webp', ?, ?)`
      )
      .run(userId, name, kind, iso(now()), iso(now())).lastInsertRowid
  );
}

function wardrobeOf(userId) {
  return {
    coat: addPiece(userId, 'Camel wool coat', 'coat'),
    shirt: addPiece(userId, 'White cotton shirt', 'shirt'),
    tee: addPiece(userId, 'Pale pink t-shirt', 't-shirt'),
    trousers: addPiece(userId, 'Navy wool trousers', 'trousers'),
    loafers: addPiece(userId, 'Black leather loafers', 'loafers'),
    bag: addPiece(userId, 'Black leather bag', 'bag'),
    tote: addPiece(userId, 'Canvas tote', 'bag'),
  };
}

// The prompt number Claude sees for a piece: its place in the member's wardrobe, 1 to N.
function numberOf(userId, pieceId) {
  return lookPhoto.wardrobeOf(userId).find((entry) => entry.piece.id === pieceId).number;
}

// A photo as the iPhone sends it: a JPEG with the place it was taken in its EXIF.
async function photo() {
  const bytes = await sharp({ create: { width: 1500, height: 2600, channels: 3, background: '#9A5E48' } })
    .jpeg()
    .withExif({
      IFD0: { Make: 'Apple', Model: 'iPhone 14 Pro' },
      IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '52/1 22/1 0/1', GPSLongitudeRef: 'E', GPSLongitude: '4/1 53/1 0/1' },
    })
    .toBuffer();
  return bytes.toString('base64');
}

const file = (relative) => path.join(dataDir, relative);

test('looks from a photo are closed until the wardrobe opens', async () => {
  const { id, token } = addMember();
  db.prepare('UPDATE users SET unlocked_at = NULL WHERE id = ?').run(id);
  assert.equal((await call('POST', '/me/looks/spot', { token, body: { photo: await photo() } })).status, 403);
  assert.equal((await call('POST', '/me/looks/photo', { token, body: {} })).status, 403);
});

test("spotting names only the member's own pieces; sure ones are ticked, a low one is asked about", async () => {
  const marta = addMember();
  const sara = addMember();
  const p = wardrobeOf(marta.id);
  wardrobeOf(sara.id);

  nextAnswer = () => ({
    worn: [
      { piece: numberOf(marta.id, p.tee), certainty: 'low' },
      { piece: numberOf(marta.id, p.coat), certainty: 'high' },
      { piece: numberOf(marta.id, p.shirt), certainty: 'medium' },
      { piece: numberOf(marta.id, p.coat), certainty: 'high' },
      { piece: '999', certainty: 'high' },
      { piece: numberOf(marta.id, p.loafers), certainty: 'high' },
    ],
    not_in_wardrobe: [{ kind: 'jeans', description: 'blue straight jeans' }],
    photo_quality: 'clear',
  });
  const before = db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'look from a photo'`).pluck().get(marta.id);
  const res = await call('POST', '/me/looks/spot', { token: marta.token, body: { photo: await photo() } });
  assert.equal(res.status, 200);

  // Claude may only answer with Marta's own pieces: the form lists her numbers, not Sara's.
  const allowed = lastPrompt.schema.properties.worn.items.properties.piece.enum;
  assert.equal(allowed.length, 7);
  const lines = lastPrompt.prompt.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
  assert.ok(lines.includes('Pale pink t-shirt') && !lines.includes('Piece 8'), 'only her wardrobe is in the prompt');

  assert.deepEqual(
    res.body.spotted.map((s) => [s.piece.id, s.certainty, s.ticked]),
    [
      [p.coat, 'high', true],
      [p.loafers, 'high', true],
      [p.shirt, 'medium', true],
      [p.tee, 'low', false],
    ],
    'sure ones first, each piece once, an unknown number dropped, low not ticked'
  );
  assert.deepEqual(res.body.notInWardrobe, [{ kind: 'jeans', description: 'Blue straight jeans' }]);
  const after = db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'look from a photo'`).pluck().get(marta.id);
  assert.equal(after, before + 1, 'one AI action');
  assert.equal(fs.existsSync(file(`photos/${marta.id}`)), false, 'nothing is stored by spotting');
});

test('a second sure piece for a taken slot is asked about, not ticked', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  nextAnswer = () => ({
    worn: [
      { piece: numberOf(id, p.shirt), certainty: 'high' },
      { piece: numberOf(id, p.tee), certainty: 'high' },
    ],
    not_in_wardrobe: [],
    photo_quality: 'clear',
  });
  const res = await call('POST', '/me/looks/spot', { token, body: { photo: await photo() } });
  assert.deepEqual(res.body.spotted.map((s) => s.ticked), [true, false]);
});

test('when Claude fails, the app gets a plain message', async () => {
  const { id, token } = addMember();
  wardrobeOf(id);
  const { ClaudeError } = require('../src/lib/claude');
  nextAnswer = () => {
    throw new ClaudeError('Claude is busy (rate limit).');
  };
  const res = await call('POST', '/me/looks/spot', { token, body: { photo: await photo() } });
  assert.equal(res.status, 502);
  assert.equal(res.body.error, 'Caro could not find your pieces this time. Try again, or add them yourself.');
  assert.equal((await call('POST', '/me/looks/spot', { token, body: { photo: 'bm90IGEgcGhvdG8=' } })).status, 400);
});

test('confirming saves a look from the photo; a second photo of the same look is added to it', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const office = byName(id, 'occasions').Office;

  const first = await call('POST', '/me/looks/photo', {
    token,
    body: { photo: await photo(), pieces: [p.coat, p.shirt, p.trousers, p.loafers], occasions: [office], seasons: [] },
  });
  assert.equal(first.status, 201);
  assert.equal(first.body.addedTo, false);
  const look = first.body.look;
  assert.equal(look.source, 'photo');
  assert.equal(look.photos.length, 1);
  assert.deepEqual(look.occasions, [office]);

  const row = db.prepare('SELECT * FROM look_photos WHERE look_id = ?').get(look.id);
  const stored = await sharp(file(row.photo_path)).metadata();
  assert.equal(stored.format, 'jpeg');
  assert.equal(Math.max(stored.width, stored.height), 2000, 'resized to 2000 on the long side');
  assert.equal(stored.exif, undefined, 'no location data kept');
  assert.equal((await sharp(file(row.thumb_path)).metadata()).format, 'webp');

  // The same main pieces with another bag: the same look.
  const second = await call('POST', '/me/looks/photo', {
    token,
    body: { photo: await photo(), pieces: [p.coat, p.shirt, p.trousers, p.loafers, p.tote], occasions: [], seasons: [] },
  });
  assert.equal(second.status, 200);
  assert.equal(second.body.addedTo, true);
  assert.equal(second.body.look.id, look.id);
  assert.equal(second.body.look.photos.length, 2);
  assert.deepEqual(second.body.look.pieces.map((x) => x.id), [p.coat, p.shirt, p.trousers, p.loafers], 'the look itself is not changed');
  assert.equal((await call('GET', '/me/looks', { token })).body.looks.length, 1);

  // Another top is another look.
  const third = await call('POST', '/me/looks/photo', {
    token,
    body: { photo: await photo(), pieces: [p.coat, p.tee, p.trousers, p.loafers] },
  });
  assert.equal(third.status, 201);
  assert.equal(third.body.look.number, 2);
});

test('a built look with the same main pieces as another is not saved twice', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const one = (await call('POST', '/me/looks', { token, body: { pieces: [p.shirt, p.trousers, p.loafers, p.bag] } })).body.look;
  const again = await call('POST', '/me/looks', { token, body: { pieces: [p.shirt, p.trousers, p.loafers, p.tote] } });
  assert.equal(again.status, 409);
  assert.equal(again.body.error, `You already have this look: No. ${one.number}.`);
  assert.deepEqual(again.body.look, { id: one.id, number: one.number });

  // Changing a look into a copy of another is refused too; changing it on its own is fine.
  const two = (await call('POST', '/me/looks', { token, body: { pieces: [p.tee, p.trousers, p.loafers] } })).body.look;
  assert.equal((await call('PUT', `/me/looks/${two.id}`, { token, body: { pieces: [p.shirt, p.trousers, p.loafers] } })).status, 409);
  assert.equal((await call('PUT', `/me/looks/${one.id}`, { token, body: { pieces: [p.shirt, p.trousers, p.loafers, p.tote] } })).status, 200);

  // Only a bag and accessories: never the same as another look.
  assert.equal((await call('POST', '/me/looks', { token, body: { pieces: [p.bag, addPiece(id, 'Silk scarf', 'scarf')] } })).status, 201);
});

test('photos are added and removed on a look, served only to their owner, and go with the look', async () => {
  const marta = addMember();
  const sara = addMember();
  const p = wardrobeOf(marta.id);
  const look = (await call('POST', '/me/looks', { token: marta.token, body: { pieces: [p.shirt, p.trousers] } })).body.look;

  const added = await call('POST', `/me/looks/${look.id}/photos`, { token: marta.token, body: { photo: await photo() } });
  assert.equal(added.status, 201);
  const [first] = added.body.look.photos;
  assert.ok(first.photo.startsWith(`/me/looks/${look.id}/photos/${first.id}/photo?v=`));

  const own = await fetch(base + first.thumb, { headers: { Authorization: `Bearer ${marta.token}` } });
  assert.equal(own.status, 200);
  const other = await fetch(base + first.photo, { headers: { Authorization: `Bearer ${sara.token}` } });
  assert.equal(other.status, 404, "another member never gets Marta's photo");
  assert.equal((await fetch(base + first.photo)).status, 401);
  assert.equal((await call('POST', `/me/looks/${look.id}/photos`, { token: sara.token, body: { photo: await photo() } })).status, 404);
  assert.equal((await call('DELETE', `/me/looks/${look.id}/photos/${first.id}`, { token: sara.token })).status, 404);

  const row = db.prepare('SELECT * FROM look_photos WHERE id = ?').get(first.id);
  const removed = await call('DELETE', `/me/looks/${look.id}/photos/${first.id}`, { token: marta.token });
  assert.equal(removed.status, 200);
  assert.deepEqual(removed.body.look.photos, []);
  assert.equal(fs.existsSync(file(row.photo_path)), false);
  assert.equal(fs.existsSync(file(row.thumb_path)), false);

  // Deleting the look deletes its photo files.
  const again = (await call('POST', `/me/looks/${look.id}/photos`, { token: marta.token, body: { photo: await photo() } })).body.look.photos[0];
  const againRow = db.prepare('SELECT * FROM look_photos WHERE id = ?').get(again.id);
  await call('DELETE', `/me/looks/${look.id}`, { token: marta.token });
  assert.equal(fs.existsSync(file(againRow.photo_path)), false);
});

test("removing the last piece of a look removes the look's photo files", async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  const look = (
    await call('POST', '/me/looks/photo', { token, body: { photo: await photo(), pieces: [p.shirt, p.trousers] } })
  ).body.look;
  const row = db.prepare('SELECT * FROM look_photos WHERE look_id = ?').get(look.id);
  await call('DELETE', `/me/pieces/${p.shirt}`, { token });
  assert.equal(fs.existsSync(file(row.photo_path)), true, 'the look still has a piece');
  await call('DELETE', `/me/pieces/${p.trousers}`, { token });
  assert.equal((await call('GET', `/me/looks/${look.id}`, { token })).status, 404);
  assert.equal(fs.existsSync(file(row.photo_path)), false);
  assert.equal(fs.existsSync(file(row.thumb_path)), false);
});
