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
const pieceDetails = require('../src/lib/piece-details');
const pieceQueue = require('../src/jobs/piece-queue');
const { seasonsByWarmth } = require('../src/lib/piece-seasons');
const setup = require('../src/lib/setup');

// The fake Claude. Each test can set what it answers next; by default a cream linen shirt.
const SHIRT = {
  name: 'cream linen shirt',
  kind: 'shirt',
  chapter: 'tops',
  colours: ['cream'],
  pattern: 'plain',
  material: 'linen',
  warmth: 'light',
  formality: 'smart casual',
  single_piece: true,
  unsure_about: [],
};
const claude = { calls: 0, answer: SHIRT, fails: false, delay: 0 };
pieceDetails.remote.claude = async (photo) => {
  claude.calls += 1;
  assert.ok(photo.length > 100, 'Claude gets the photo');
  if (claude.delay) await new Promise((resolve) => setTimeout(resolve, claude.delay));
  if (claude.fails) throw new Error('Claude is busy');
  return claude.answer;
};
// Comparing with the member's other pieces has its own tests (lookalikes.test.js): here nothing looks alike.
require('../src/lib/lookalikes').remote.claude = async () => ({ same: [] });

// Official 1991 to 2020 normals (the same as setup.test.js).
const CITIES = {
  amsterdam: { id: 2759794, name: 'Amsterdam', country: 'NL', latitude: 52.37, high: [6.2, 6.9, 10.1, 14.3, 17.8, 20.3, 22.5, 22.4, 19.2, 14.7, 10.0, 6.9] },
  miami: { id: 4164138, name: 'Miami', country: 'US', latitude: 25.77, high: [24.6, 25.7, 27.0, 28.7, 30.4, 31.8, 32.6, 32.6, 31.7, 29.9, 27.4, 25.7] },
  buenosAires: { id: 3435910, name: 'Buenos Aires', country: 'AR', latitude: -34.61, high: [30.1, 28.9, 27.0, 23.2, 19.4, 16.4, 15.5, 17.9, 19.7, 22.6, 26.0, 29.0] },
};

const YEARS = {
  four: [
    { name: 'Spring', months: [3, 4, 5] },
    { name: 'Summer', months: [6, 7, 8] },
    { name: 'Autumn', months: [9, 10, 11] },
    { name: 'Winter', months: [12, 1, 2] },
  ],
  fourSouth: [
    { name: 'Spring', months: [9, 10, 11] },
    { name: 'Summer', months: [12, 1, 2] },
    { name: 'Autumn', months: [3, 4, 5] },
    { name: 'Winter', months: [6, 7, 8] },
  ],
  miami: [
    { name: 'Hot and rainy', months: [5, 6, 7, 8, 9, 10] },
    { name: 'Mild and dry', months: [11, 12, 1, 2, 3, 4] },
  ],
  warmCool: [
    { name: 'Warm', months: [4, 5, 6, 7, 8, 9] },
    { name: 'Cool', months: [10, 11, 12, 1, 2, 3] },
  ],
};

// Gives a member a city with its typical weather, and a year.
function giveYear(userId, cityKey, year) {
  const city = CITIES[cityKey];
  db.prepare(
    `INSERT INTO cities (id, name, country, latitude, longitude, created_at) VALUES (?, ?, ?, ?, 0, ?) ON CONFLICT (id) DO NOTHING`
  ).run(city.id, city.name, city.country, city.latitude, iso(now()));
  const addMonth = db.prepare('INSERT OR REPLACE INTO city_weather (city_id, month, high_c, rain_mm) VALUES (?, ?, ?, 50)');
  city.high.forEach((high, i) => addMonth.run(city.id, i + 1, high));
  db.prepare('UPDATE users SET city_id = ?, city = ?, country = ? WHERE id = ?').run(city.id, city.name, city.country, userId);
  setup.saveSeasons(userId, year);
}

// The member's seasons by name: { Spring: 12, ... }
function seasonIds(userId) {
  return Object.fromEntries(db.prepare('SELECT name, id FROM seasons WHERE user_id = ?').all(userId).map((s) => [s.name, s.id]));
}

function seasonNames(userId, ids) {
  const byId = Object.fromEntries(Object.entries(seasonIds(userId)).map(([name, id]) => [id, name]));
  return ids.map((id) => byId[id]);
}

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

// Adds a piece and, unless told not to, waits until Claude (the fake) has read it.
async function addPiece(token, { withCutout = true, wait = true } = {}) {
  const added = await call('POST', '/me/pieces', {
    token,
    body: { photo: await photoWithLocation(), cutout: withCutout ? await cutOut() : null },
  });
  assert.equal(added.status, 201, added.body.error);
  if (wait) await pieceQueue.idle();
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

// Suggested details

test('Claude suggests the details in the background, checked against the fixed lists', async () => {
  const { id, token } = addMember();
  giveYear(id, 'amsterdam', YEARS.four);
  claude.answer = { ...SHIRT, colours: ['cream', 'mauve', 'cream', 'navy'], material: 'tweed' };

  const piece = await addPiece(token);
  assert.equal(piece.detailsStatus, 'reading', 'the upload answers before Claude does');
  await pieceQueue.idle();

  const row = pieceRow(piece.id);
  assert.equal(row.details_status, 'suggested');
  assert.equal(row.status, 'pending', 'still waiting for the member to confirm');
  assert.equal(row.name, 'Cream linen shirt');
  assert.equal(row.kind, 'shirt');
  assert.equal(row.material, null, 'a material not on the list is left for the member');
  assert.equal(row.warmth, 'light');
  assert.deepEqual(db.prepare('SELECT colour FROM piece_colours WHERE piece_id = ? ORDER BY position').pluck().all(piece.id), ['cream', 'navy']);
  const seasons = db.prepare('SELECT season_id FROM piece_seasons WHERE piece_id = ?').pluck().all(piece.id);
  assert.deepEqual(seasonNames(id, seasons).sort(), ['Spring', 'Summer']);
  assert.equal(db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'piece details'`).pluck().get(id), 1);
  claude.answer = SHIRT;
});

test('when Claude cannot answer, the piece is "not read" and still waits for review', async () => {
  const { token } = addMember();
  claude.fails = true;
  const piece = await addPiece(token);
  await pieceQueue.idle();
  claude.fails = false;

  const row = pieceRow(piece.id);
  assert.equal(row.details_status, 'not read');
  assert.equal(row.status, 'pending');
  assert.equal(row.name, null);
});

test('a piece removed while Claude reads it stays removed', async () => {
  const { token } = addMember();
  claude.delay = 50;
  const piece = await addPiece(token, { wait: false });
  await call('DELETE', `/me/pieces/${piece.id}`, { token });
  await pieceQueue.idle();
  claude.delay = 0;
  assert.equal(pieceRow(piece.id), undefined);
});

// Seasons from warmth

function namesByWarmth(userId) {
  const rule = seasonsByWarmth(userId);
  return Object.fromEntries(Object.entries(rule).map(([warmth, ids]) => [warmth, seasonNames(userId, ids)]));
}

test('in the Netherlands: light is spring and summer, warm is autumn and winter, medium is all four', () => {
  const { id } = addMember();
  giveYear(id, 'amsterdam', YEARS.four);
  assert.deepEqual(namesByWarmth(id), {
    light: ['Spring', 'Summer'],
    medium: ['Spring', 'Summer', 'Autumn', 'Winter'],
    warm: ['Autumn', 'Winter'],
  });
});

test('in Miami: light and medium are both seasons, warm is mild and dry', () => {
  const { id } = addMember();
  giveYear(id, 'miami', YEARS.miami);
  assert.deepEqual(namesByWarmth(id), {
    light: ['Hot and rainy', 'Mild and dry'],
    medium: ['Hot and rainy', 'Mild and dry'],
    warm: ['Mild and dry'],
  });
});

test('in the south, the seasons follow the year: light is spring and summer in Buenos Aires', () => {
  const { id } = addMember();
  giveYear(id, 'buenosAires', YEARS.fourSouth);
  assert.deepEqual(namesByWarmth(id).light, ['Spring', 'Summer']);
  assert.deepEqual(namesByWarmth(id).warm, ['Autumn', 'Winter']);
});

test('two seasons where the cool one is cold: light skips it', () => {
  const { id } = addMember();
  giveYear(id, 'amsterdam', YEARS.warmCool);
  assert.deepEqual(namesByWarmth(id), { light: ['Warm'], medium: ['Warm', 'Cool'], warm: ['Cool'] });
});

test('with no seasons, or no known weather, nothing is proposed', () => {
  const { id } = addMember();
  giveYear(id, 'amsterdam', []);
  assert.deepEqual(seasonsByWarmth(id), { light: [], medium: [], warm: [] });
  const other = addMember();
  setup.saveSeasons(other.id, YEARS.four);
  assert.deepEqual(seasonsByWarmth(other.id), { light: [], medium: [], warm: [] });
});

test('changing from four seasons to two proposes new seasons for every piece', async () => {
  const { id, token } = addMember();
  giveYear(id, 'amsterdam', YEARS.four);
  claude.answer = { ...SHIRT, name: 'grey wool coat', kind: 'coat', chapter: 'outerwear', warmth: 'warm' };
  const piece = await addPiece(token);
  await pieceQueue.idle();
  claude.answer = SHIRT;
  const seasonsOf = () => seasonNames(id, db.prepare('SELECT season_id FROM piece_seasons WHERE piece_id = ?').pluck().all(piece.id)).sort();
  assert.deepEqual(seasonsOf(), ['Autumn', 'Winter']);

  setup.saveSeasons(id, YEARS.warmCool);
  assert.deepEqual(seasonsOf(), ['Cool']);

  // Renaming, with the same number of seasons, keeps them.
  setup.saveSeasons(id, [{ name: 'Summer half', months: YEARS.warmCool[0].months }, { name: 'Winter half', months: YEARS.warmCool[1].months }]);
  assert.deepEqual(seasonsOf(), ['Winter half']);
});

// The review queue, the unlock rule and the edit

// Confirmed pieces put straight into the database, for the unlock tests. kinds: ['jumper', ...]
function addConfirmed(userId, kinds, status = 'confirmed') {
  const add = db.prepare(
    `INSERT INTO pieces (user_id, status, name, kind, details_status, original_path, thumb_path, created_at, confirmed_at)
     VALUES (?, ?, ?, ?, 'suggested', 'photos/none-photo.jpg', 'photos/none-thumb.webp', ?, ?)`
  );
  return kinds.map((kind) => Number(add.run(userId, status, `Test ${kind}`, kind, iso(now()), iso(now())).lastInsertRowid));
}

// 19 pieces with tops and bottoms but no shoes, like npm run seed-wardrobe.
const NINETEEN = [
  'coat', 'blazer', 'jacket',
  'jumper', 'cardigan', 'sweatshirt', 'knitted vest',
  'shirt', 't-shirt', 'blouse', 'long-sleeved top', 'tank top',
  'trousers', 'jeans', 'leggings',
  'skirt', 'dress', 'jumpsuit',
  'bag',
];

function details(overrides = {}) {
  return { name: 'Black leather trainers', kind: 'trainers', colours: ['black'], pattern: 'plain', material: 'leather', warmth: 'medium', formality: 'casual', seasons: [], occasions: [], status: 'confirmed', ...overrides };
}

test('19 pieces without shoes stay locked; a pair of shoes opens Looks and Get the look, once', async () => {
  const { id, token } = addMember();
  addConfirmed(id, NINETEEN);

  let wardrobe = (await call('GET', '/me/wardrobe', { token })).body;
  assert.deepEqual(wardrobe.progress, { pieces: 19, needed: 20, top: true, bottomOrOnePiece: true, shoes: false, unlocked: false });

  claude.answer = { ...SHIRT, name: 'black leather trainers', kind: 'trainers', chapter: 'shoes', warmth: 'medium' };
  const shoes = await addPiece(token);
  claude.answer = SHIRT;
  wardrobe = (await call('GET', '/me/wardrobe', { token })).body;
  assert.equal(wardrobe.progress.pieces, 19, 'waiting for review does not count');
  assert.deepEqual(wardrobe.waiting, { reading: 0, toReview: 1 });

  const confirmed = await call('PUT', `/me/pieces/${shoes.id}`, { token, body: details() });
  assert.equal(confirmed.status, 200, confirmed.body.error);
  assert.equal(confirmed.body.justUnlocked, true);
  assert.deepEqual(confirmed.body.progress, { pieces: 20, needed: 20, top: true, bottomOrOnePiece: true, shoes: true, unlocked: true });
  assert.equal(confirmed.body.piece.status, 'confirmed');
  assert.ok(confirmed.body.piece.confirmedAt);

  const me = (await call('GET', '/me', { token })).body.member;
  assert.equal(me.unlocked, true);

  // Saving the same piece again does not open it a second time.
  const again = await call('PUT', `/me/pieces/${shoes.id}`, { token, body: details({ name: 'White trainers' }) });
  assert.equal(again.body.justUnlocked, false);
});

test('removing pieces afterwards keeps Looks and Get the look open', async () => {
  const { id, token } = addMember();
  const ids = addConfirmed(id, [...NINETEEN, 'loafers']);
  const unlocked = await call('PUT', `/me/pieces/${ids[0]}`, { token, body: details({ name: 'Camel coat', kind: 'coat' }) });
  assert.equal(unlocked.body.justUnlocked, true);

  for (const pieceId of ids.slice(-6)) {
    const removed = await call('DELETE', `/me/pieces/${pieceId}`, { token });
    assert.equal(removed.status, 200);
  }
  const wardrobe = (await call('GET', '/me/wardrobe', { token })).body;
  assert.equal(wardrobe.progress.pieces, 14);
  assert.equal(wardrobe.progress.shoes, false);
  assert.equal(wardrobe.progress.unlocked, true);
});

test('maybe counts, waiting does not; 20 pieces need a top, a bottom or one-piece, and shoes', async () => {
  const { id, token } = addMember();
  const ids = addConfirmed(id, [...NINETEEN.slice(0, 18), 'trainers']);
  const [pending] = addConfirmed(id, ['heels'], 'pending');
  assert.equal((await call('GET', '/me/wardrobe', { token })).body.progress.pieces, 19);

  const maybe = await call('PUT', `/me/pieces/${pending}`, { token, body: details({ name: 'Red heels', kind: 'heels', status: 'maybe' }) });
  assert.equal(maybe.body.piece.status, 'maybe');
  assert.equal(maybe.body.justUnlocked, true, 'a maybe piece counts');

  // Twenty pieces with no top stay locked.
  const other = addMember();
  addConfirmed(other.id, ['coat', 'coat', 'coat', 'jeans', 'jeans', 'jeans', 'trainers', 'bag', 'bag', 'bag', 'bag', 'belt', 'belt', 'scarf', 'scarf', 'hat', 'hat', 'sunglasses', 'jewellery', 'dress']);
  const progress = (await call('GET', '/me/wardrobe', { token: other.token })).body.progress;
  assert.equal(progress.pieces, 20);
  assert.equal(progress.top, false);
  assert.equal(progress.unlocked, false);
  assert.ok(ids.length);
});

test('the details are checked: the fixed lists, a name, and only the member\'s own seasons and occasions', async () => {
  const owner = addMember('Owner');
  const other = addMember('Other');
  giveYear(owner.id, 'amsterdam', YEARS.four);
  giveYear(other.id, 'amsterdam', YEARS.four);
  const piece = await addPiece(owner.token);
  const put = (body, token = owner.token) => call('PUT', `/me/pieces/${piece.id}`, { token, body });

  assert.equal((await put(details({ name: ' ' }))).body.error, 'Name this piece.');
  assert.equal((await put(details({ kind: 'cape' }))).status, 400);
  assert.equal((await put(details({ colours: ['black', 'mauve'] }))).status, 400);
  assert.equal((await put(details({ colours: ['black', 'white', 'red', 'blue'] }))).status, 400);
  assert.equal((await put(details({ material: 'tweed' }))).status, 400);
  assert.equal((await put(details({ status: 'pending' }))).status, 400);
  assert.equal((await put(details({ seasons: [Object.values(seasonIds(other.id))[0]] }))).status, 400, "another member's season");
  const otherOccasion = db.prepare('SELECT id FROM occasions WHERE user_id = ?').pluck().get(other.id);
  assert.equal((await put(details({ occasions: [otherOccasion] }))).status, 400, "another member's occasion");
  assert.equal((await put(details(), other.token)).status, 404, "another member's piece");

  const ownSeason = seasonIds(owner.id).Summer;
  const ownOccasion = db.prepare('SELECT id FROM occasions WHERE user_id = ? ORDER BY position').pluck().get(owner.id);
  const saved = await put(details({ name: 'cream linen shirt', kind: 'shirt', colours: ['cream', 'navy'], seasons: [ownSeason], occasions: [ownOccasion] }));
  assert.equal(saved.status, 200, saved.body.error);
  assert.equal(saved.body.piece.name, 'Cream linen shirt');
  assert.equal(saved.body.piece.chapter, 'tops');
  assert.equal(saved.body.piece.slot, 'top');
  assert.deepEqual(saved.body.piece.colours, ['cream', 'navy']);
  assert.deepEqual(saved.body.piece.seasons, [ownSeason]);
  assert.deepEqual(saved.body.piece.occasions, [ownOccasion]);
});

test('the review queue lists the member\'s own pieces waiting for review, with the season rule', async () => {
  const owner = addMember('Owner');
  const other = addMember('Other');
  giveYear(owner.id, 'miami', YEARS.miami);
  const first = await addPiece(owner.token);
  const second = await addPiece(owner.token);
  await addPiece(other.token);
  await call('PUT', `/me/pieces/${first.id}`, { token: owner.token, body: details() });

  const queue = (await call('GET', '/me/pieces?status=pending', { token: owner.token })).body;
  assert.deepEqual(queue.pieces.map((p) => p.id), [second.id]);
  assert.equal(queue.pieces[0].detailsStatus, 'suggested');
  assert.equal(queue.pieces[0].name, 'Cream linen shirt');
  assert.equal(queue.pieces[0].seasons.length, 2, 'light in Miami: both seasons');
  assert.equal(queue.seasonsByWarmth.warm.length, 1);
  assert.deepEqual(queue.seasons.map((season) => season.name), ['Hot and rainy', 'Mild and dry']);
  assert.deepEqual(queue.occasions.map((occasion) => occasion.name), ['Office', 'Working from home', 'Night out', 'Day out']);

  const chapter = (await call('GET', '/me/pieces?chapter=shoes', { token: owner.token })).body;
  assert.deepEqual(chapter.pieces.map((p) => p.id), [first.id]);
  assert.equal((await call('GET', '/me/pieces', { token: owner.token })).status, 400);
});

test('the edit shows each chapter with its count and three newest cut-outs', async () => {
  const { id, token } = addMember();
  addConfirmed(id, ['jumper', 'cardigan', 'hoodie', 'jeans']);
  const wardrobe = (await call('GET', '/me/wardrobe', { token })).body;
  assert.deepEqual(wardrobe.chapters.map((c) => [c.number, c.name, c.count, c.thumbs.length]), [
    [2, 'knitwear', 3, 3],
    [4, 'trousers', 1, 1],
  ]);
});

test('the app knows when the wardrobe is started, and step 6 shows until then', async () => {
  const { token } = addMember();
  assert.equal((await call('GET', '/me', { token })).body.member.wardrobeStarted, false);
  await addPiece(token);
  const member = (await call('GET', '/me', { token })).body.member;
  assert.equal(member.wardrobeStarted, true);
  assert.equal(member.unlocked, false);
});

test('retake gives a piece a new photo and keeps its details, without asking Claude again', async () => {
  const { token } = addMember();
  const piece = await addPiece(token, { withCutout: false });
  const before = pieceRow(piece.id);
  const calls = claude.calls;

  const retaken = await call('PUT', `/me/pieces/${piece.id}/photo`, { token, body: { photo: await photoWithLocation(1200, 1600), cutout: await cutOut() } });
  assert.equal(retaken.status, 200, retaken.body.error);
  assert.equal(retaken.body.piece.name, 'Cream linen shirt');
  assert.ok(retaken.body.piece.images.cutout);
  assert.notEqual(retaken.body.piece.images.photo, piece.images.photo, 'a new address, so the old copy is not shown');
  assert.equal(claude.calls, calls);
  assert.ok(!fs.existsSync(file(before.original_path)), 'the old photo is deleted');
  assert.ok(fs.existsSync(file(pieceRow(piece.id).original_path)));
});

test('the fixed lists for the app', async () => {
  const { token } = addMember();
  const lists = (await call('GET', '/lists', { token })).body;
  assert.equal(lists.chapters.length, 7);
  assert.equal(lists.chapters[4].name, 'dresses and skirts');
  assert.deepEqual(lists.chapters[4].kinds.map((k) => k.name), ['dress', 'jumpsuit', 'skirt']);
  assert.equal(lists.colours.length, 21);
  assert.deepEqual(lists.warmth, ['light', 'medium', 'warm']);
  assert.equal((await call('GET', '/lists')).status, 401);
});

test('a photo taken sideways can be turned a quarter turn; only by its owner', async () => {
  const owner = addMember('Owner');
  const other = addMember('Other');
  const piece = await addPiece(owner.token);
  const before = pieceRow(piece.id);
  const size = async (relative) => {
    const { width, height } = await sharp(file(relative)).metadata();
    return [width, height];
  };
  const [photoWidth, photoHeight] = await size(before.original_path);
  const [cutWidth, cutHeight] = await size(before.cutout_path);

  assert.equal((await call('POST', `/me/pieces/${piece.id}/rotate`, { token: other.token })).status, 404);

  const turned = await call('POST', `/me/pieces/${piece.id}/rotate`, { token: owner.token });
  assert.equal(turned.status, 200, turned.body.error);
  assert.notEqual(turned.body.piece.images.thumb, piece.images.thumb, 'a new address, so the old copy is not shown');
  assert.equal(turned.body.piece.name, 'Cream linen shirt', 'the details stay');

  const after = pieceRow(piece.id);
  assert.deepEqual(await size(after.original_path), [photoHeight, photoWidth]);
  assert.deepEqual(await size(after.cutout_path), [cutHeight, cutWidth]);
  assert.equal((await sharp(file(after.cutout_path)).metadata()).hasAlpha, true);
  for (const old of [before.original_path, before.cutout_path, before.thumb_path]) {
    assert.ok(!fs.existsSync(file(old)), `${old} deleted`);
  }
});
