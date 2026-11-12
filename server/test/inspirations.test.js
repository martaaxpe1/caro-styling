// npm test
// Checks Get the look (PRD sections 6 to 8, ticket T10): an inspiration is read in the
// background, Claude may only name the member's own pieces, "N of M yours" counts yours and
// filled pieces but not close, a missing piece marked as key goes on To find, the fact "in N
// of your inspirations", saving your version as a look with the same look rule, Pinterest
// links, and that one member never reaches another's inspiration. Claude and Pinterest are
// replaced by stand-ins, so nothing outside is called.

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const sharp = require('sharp');

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caro-test-'));
process.env.DATA_DIR = dataDir;
process.env.DEV_TODAY = '2026-10-30';
delete process.env.NODE_ENV;

const db = require('../src/db');
const app = require('../src/app');
const { makeToken, hashToken } = require('../src/lib/auth');
const { now, iso } = require('../src/lib/today');
const inspiration = require('../src/lib/inspiration');
const lookPhoto = require('../src/lib/look-photo');
const sharedLink = require('../src/lib/shared-link');
const queue = require('../src/jobs/inspiration-queue');

// The stand-in for Claude: answers with whatever the test sets, given the numbers it may use.
let nextAnswer = () => ({ pieces: [] });
let lastPrompt = null;
inspiration.remote.claude = async ({ prompt, schema }) => {
  lastPrompt = { prompt, schema };
  const answer = nextAnswer(schema.properties.pieces.items.properties.closest_piece.enum);
  if (answer instanceof Error) throw answer;
  return answer;
};

// The stand-in for Pinterest.
let pinterestCalls = 0;
sharedLink.remote.imageFromLink = async (link) => {
  pinterestCalls += 1;
  return { image: Buffer.from(await photo(), 'base64'), link: 'https://www.pinterest.com/pin/123/' };
};

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
  return { status: res.status, body: await res.json().catch(() => null) };
}

let memberCount = 0;
function addMember() {
  memberCount += 1;
  const at = iso(now());
  const id = Number(
    db
      .prepare(`INSERT INTO users (email, name, status, onboarding_step, unlocked_at, created_at) VALUES (?, 'Test', 'active', 6, ?, ?)`)
      .run(`inspired${memberCount}@example.test`, at, at).lastInsertRowid
  );
  const token = makeToken();
  db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, hashToken(token), at, at);
  require('../src/lib/occasions').proposeFor(id);
  return { id, token };
}

function addPiece(userId, name, kind, colour) {
  const id = Number(
    db
      .prepare(
        `INSERT INTO pieces (user_id, status, name, kind, details_status, original_path, thumb_path, created_at, confirmed_at)
         VALUES (?, 'confirmed', ?, ?, 'suggested', 'photos/none-photo.jpg', 'photos/none-thumb.webp', ?, ?)`
      )
      .run(userId, name, kind, iso(now()), iso(now())).lastInsertRowid
  );
  if (colour) db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, 1)').run(userId, id, colour);
  return id;
}

function wardrobeOf(userId) {
  return {
    blazer: addPiece(userId, 'Chocolate blazer', 'blazer', 'brown'),
    tee: addPiece(userId, 'Ecru cotton tee', 't-shirt', 'cream'),
    jeans: addPiece(userId, 'Dark straight jeans', 'jeans', 'blue'),
    loafers: addPiece(userId, 'Black loafers', 'loafers', 'black'),
    tote: addPiece(userId, 'Canvas tote', 'bag', 'beige'),
  };
}

const numberOf = (userId, pieceId) => lookPhoto.wardrobeOf(userId).find((entry) => entry.piece.id === pieceId).number;

async function photo() {
  const bytes = await sharp({ create: { width: 800, height: 1200, channels: 3, background: '#D3C7B6' } })
    .jpeg()
    .withExif({ IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '52/1 22/1 0/1', GPSLongitudeRef: 'E', GPSLongitude: '4/1 53/1 0/1' } })
    .toBuffer();
  return bytes.toString('base64');
}

const described = (over) => ({
  colours: ['black'],
  pattern: 'plain',
  material: 'not sure',
  shape: 'straight',
  x: 50,
  y: 50,
  closest_piece: 'none',
  match: 'missing',
  ...over,
});

// The inspiration of screen 15: a grey blazer (close), a white tee and jeans (yours), black
// loafers (yours), and a small black bag (missing; the canvas tote is the nearest bag).
function screen15(userId, p) {
  return () => ({
    pieces: [
      described({ description: 'Grey oversized blazer', kind: 'blazer', chapter: 'outerwear', colours: ['grey'], closest_piece: numberOf(userId, p.blazer), match: 'close', x: 30, y: 25 }),
      described({ description: 'White tee', kind: 't-shirt', chapter: 'tops', colours: ['white'], closest_piece: numberOf(userId, p.tee), match: 'yours', x: 120, y: -4 }),
      described({ description: 'Straight jeans', kind: 'jeans', chapter: 'trousers', colours: ['blue'], closest_piece: numberOf(userId, p.jeans), match: 'yours' }),
      described({ description: 'Black loafers', kind: 'loafers', chapter: 'shoes', closest_piece: numberOf(userId, p.loafers), match: 'yours' }),
      described({ description: 'Small black shoulder bag, with a gold chain', kind: 'bag', chapter: 'accessories', closest_piece: numberOf(userId, p.tote), match: 'close' }),
    ],
  });
}

// Adds an inspiration and waits until Claude's stand-in has read it.
async function addInspiration(token, body) {
  const res = await call('POST', '/me/inspirations', { token, body: body ?? { photo: await photo(), note: 'For autumn' } });
  await queue.idle();
  return res;
}

test('Get the look is closed until the wardrobe opens', async () => {
  const { id, token } = addMember();
  db.prepare('UPDATE users SET unlocked_at = NULL WHERE id = ?').run(id);
  assert.equal((await call('GET', '/me/inspirations', { token })).status, 403);
  assert.equal((await call('POST', '/me/inspirations', { token, body: { photo: await photo() } })).status, 403);
});

test("an inspiration is read in the background, naming only the member's own pieces", async () => {
  const marta = addMember();
  const sara = addMember();
  const p = wardrobeOf(marta.id);
  wardrobeOf(sara.id);
  nextAnswer = screen15(marta.id, p);

  const before = db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'inspiration'`).pluck().get(marta.id);
  const res = await call('POST', '/me/inspirations', { token: marta.token, body: { photo: await photo(), note: 'For autumn' } });
  assert.equal(res.status, 201);
  assert.equal(res.body.inspiration.status, 'reading', 'answers at once, before Claude');
  await queue.idle();

  const allowed = lastPrompt.schema.properties.pieces.items.properties.closest_piece.enum;
  assert.deepEqual(allowed, ['1', '2', '3', '4', '5', 'none'], "only Marta's five pieces");
  const lines = lastPrompt.prompt.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
  assert.ok(lines.includes('Chocolate blazer') && !lines.includes('Piece 6'));
  const after = db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'inspiration'`).pluck().get(marta.id);
  assert.equal(after, before + 1, 'one AI action');

  const page = await call('GET', `/me/inspirations/${res.body.inspiration.id}`, { token: marta.token });
  const insp = page.body.inspiration;
  assert.equal(insp.status, 'ready');
  assert.equal(insp.note, 'For autumn');
  assert.deepEqual(
    insp.pieces.map((x) => [x.number, x.description, x.match, x.piece?.id ?? null]),
    [
      [1, 'Grey oversized blazer', 'close', p.blazer],
      [2, 'White tee', 'yours', p.tee],
      [3, 'Straight jeans', 'yours', p.jeans],
      [4, 'Black loafers', 'yours', p.loafers],
      [5, 'Small black shoulder bag', 'close', p.tote],
    ]
  );
  assert.deepEqual(insp.pieces[1].pin, { x: 100, y: 0 }, 'pins stay on the photo');
  assert.deepEqual([insp.owned, insp.total], [3, 5], 'close does not count as yours');

  // Sara cannot see it, change it, save it or get its photo.
  const id = insp.id;
  assert.equal((await call('GET', `/me/inspirations/${id}`, { token: sara.token })).status, 404);
  assert.equal((await call('PUT', `/me/inspirations/${id}/pieces/5`, { token: sara.token, body: { key: true } })).status, 404);
  assert.equal((await call('POST', `/me/inspirations/${id}/look`, { token: sara.token, body: {} })).status, 404);
  assert.equal((await fetch(`${base}/me/inspirations/${id}/photo/photo`, { headers: { Authorization: `Bearer ${sara.token}` } })).status, 404);
  assert.equal((await call('DELETE', `/me/inspirations/${id}`, { token: sara.token })).status, 404);

  // The photo is stored without its location.
  const res2 = await fetch(`${base}/me/inspirations/${id}/photo/photo`, { headers: { Authorization: `Bearer ${marta.token}` } });
  assert.equal(res2.status, 200);
  const meta = await sharp(Buffer.from(await res2.arrayBuffer())).metadata();
  assert.equal(meta.exif, undefined, 'no location data');
});

test('a match in another chapter is dropped, and a missing piece keeps the nearest of its kind', () => {
  const { id } = addMember();
  const p = wardrobeOf(id);
  const pieces = inspiration.checked(
    {
      pieces: [
        described({ description: 'Black coat', kind: 'coat', chapter: 'outerwear', closest_piece: numberOf(id, p.tote), match: 'close' }),
        described({ description: 'Red loafers', kind: 'loafers', chapter: 'shoes', colours: ['red'], closest_piece: numberOf(id, p.loafers), match: 'missing' }),
        described({ description: '', kind: 'bag', chapter: 'accessories' }),
      ],
    },
    lookPhoto.wardrobeOf(id)
  );
  assert.deepEqual(
    pieces.map((x) => [x.description, x.match, x.matchedPieceId, x.colour]),
    [
      ['Black coat', 'missing', null, 'black'],
      ['Red loafers', 'missing', p.loafers, 'red'],
    ]
  );
});

test('your version: fill a piece, mark the missing one as key, To find and the fact', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  // The bag is missing: Claude says so, with the tote as the nearest bag.
  nextAnswer = () => {
    const answer = screen15(id, p)();
    answer.pieces[4].match = 'missing';
    return answer;
  };
  const first = (await addInspiration(token)).body.inspiration.id;
  const second = (await addInspiration(token)).body.inspiration.id;

  let insp = (await call('GET', `/me/inspirations/${first}`, { token })).body.inspiration;
  const bag = insp.pieces[4];
  assert.equal(bag.match, 'missing');
  assert.equal(bag.piece, null);
  assert.equal(bag.nearest.id, p.tote, 'your nearest');
  assert.equal(bag.inspirations, 2, 'in 2 of your inspirations');

  // Only a missing piece can be key.
  assert.equal((await call('PUT', `/me/inspirations/${first}/pieces/2`, { token, body: { key: true } })).status, 400);
  insp = (await call('PUT', `/me/inspirations/${first}/pieces/5`, { token, body: { key: true } })).body.inspiration;
  assert.equal(insp.pieces[4].key, true);

  let home = (await call('GET', '/me/inspirations', { token })).body;
  assert.equal(home.inspirations.length, 2);
  assert.deepEqual(
    home.toFind.map((f) => [f.description, f.status, f.searchedAt, f.inspirations]),
    [['Small black shoulder bag', 'considering', null, 2]]
  );

  // Filling the close blazer with her own counts it as yours.
  insp = (await call('PUT', `/me/inspirations/${first}/pieces/1`, { token, body: { piece: p.blazer } })).body.inspiration;
  assert.equal(insp.pieces[0].match, 'filled');
  assert.deepEqual([insp.owned, insp.total], [4, 5]);

  // Removing a piece leaves it out of the count and off To find; putting it back keeps it off.
  insp = (await call('PUT', `/me/inspirations/${first}/pieces/5`, { token, body: { removed: true } })).body.inspiration;
  assert.deepEqual([insp.owned, insp.total], [4, 4]);
  home = (await call('GET', '/me/inspirations', { token })).body;
  assert.equal(home.toFind.length, 0);
  assert.equal((await call('PUT', `/me/inspirations/${first}/pieces/5`, { token, body: { removed: false, key: true } })).status, 200);

  // Someone else's piece cannot fill it.
  const other = addMember();
  const theirs = wardrobeOf(other.id);
  assert.equal((await call('PUT', `/me/inspirations/${first}/pieces/5`, { token, body: { piece: theirs.tote } })).status, 400);
  assert.equal((await call('GET', `/me/inspirations/${first}`, { token })).body.inspiration.pieces[4].key, true, 'a refusal changes nothing');

  // Deleting the second inspiration deletes its photo files.
  const row = db.prepare('SELECT * FROM inspirations WHERE id = ?').get(second);
  assert.equal((await call('DELETE', `/me/inspirations/${second}`, { token })).status, 200);
  assert.equal(fs.existsSync(path.join(dataDir, row.photo_path)), false);
  assert.equal((await call('GET', `/me/inspirations/${first}`, { token })).body.inspiration.pieces[4].inspirations, null, 'only one now');
});

test('your version saves as an inspired look, again changes the same look, and the same look rule holds', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  nextAnswer = screen15(id, p);
  const inspId = (await addInspiration(token)).body.inspiration.id;
  const office = db.prepare(`SELECT id FROM occasions WHERE user_id = ? AND name = 'Office'`).pluck().get(id);

  let res = await call('POST', `/me/inspirations/${inspId}/look`, { token, body: { occasions: [office], seasons: [] } });
  assert.equal(res.status, 201);
  assert.equal(res.body.look.source, 'inspired');
  assert.deepEqual(res.body.look.pieces.map((x) => x.id).sort(), [p.blazer, p.tee, p.jeans, p.loafers, p.tote].sort());
  const lookId = res.body.look.id;
  assert.deepEqual((await call('GET', `/me/inspirations/${inspId}`, { token })).body.inspiration.look, { id: lookId, number: 1 });

  // Saving again after a change updates that look.
  await call('PUT', `/me/inspirations/${inspId}/pieces/5`, { token, body: { removed: true } });
  res = await call('POST', `/me/inspirations/${inspId}/look`, { token, body: { occasions: [office], seasons: [] } });
  assert.equal(res.status, 200);
  assert.equal(res.body.look.id, lookId);
  assert.equal(res.body.look.pieces.length, 4);

  // A second inspiration with the same main pieces: "You already have this look: No. 1."
  const again = (await addInspiration(token)).body.inspiration.id;
  res = await call('POST', `/me/inspirations/${again}/look`, { token, body: { occasions: [], seasons: [] } });
  assert.equal(res.status, 409);
  assert.deepEqual(res.body.look, { id: lookId, number: 1 });

  // Deleting the look keeps the inspiration.
  await call('DELETE', `/me/looks/${lookId}`, { token });
  assert.equal((await call('GET', `/me/inspirations/${inspId}`, { token })).body.inspiration.look, null);
});

test('Claude not answering leaves it "not read", and Try again reads it', async () => {
  const { id, token } = addMember();
  const p = wardrobeOf(id);
  nextAnswer = () => new Error('Claude took too long to answer.');
  const inspId = (await addInspiration(token)).body.inspiration.id;
  assert.equal((await call('GET', `/me/inspirations/${inspId}`, { token })).body.inspiration.status, 'not read');

  nextAnswer = screen15(id, p);
  await call('POST', `/me/inspirations/${inspId}/read`, { token });
  await queue.idle();
  const insp = (await call('GET', `/me/inspirations/${inspId}`, { token })).body.inspiration;
  assert.equal(insp.status, 'ready');
  assert.equal(insp.pieces.length, 5);
});

test('a Pinterest link brings its image; other links are refused', async () => {
  const { token } = addMember();
  nextAnswer = () => ({ pieces: [] });
  const calls = pinterestCalls;
  const res = await addInspiration(token, { link: 'https://pin.it/abc123' });
  assert.equal(res.status, 201);
  assert.equal(pinterestCalls, calls + 1);
  assert.equal(res.body.inspiration.link, 'https://www.pinterest.com/pin/123/');
  assert.equal(res.body.inspiration.source, 'Pinterest');

  for (const link of ['https://www.instagram.com/p/xyz/', 'http://pin.it/abc', 'https://pinterest.com.evil.test/pin/1', 'not a link']) {
    const refused = await call('POST', '/me/inspirations', { token, body: { link } });
    assert.equal(refused.status, 400, link);
  }
  assert.equal(pinterestCalls, calls + 1, 'nothing else is fetched');
  assert.ok(sharedLink.isPinterestLink('https://nl.pinterest.com/pin/1/'));
  assert.ok(sharedLink.isPinterestLink('https://www.pinterest.co.uk/pin/1/'));
  assert.equal(sharedLink.isPinterestLink('https://pinterest.com@evil.test/'), false);
});

test("the page's image tag is found in either order", () => {
  assert.equal(sharedLink.ogImage('<meta property="og:image" content="https://i.pinimg.com/736x/a.jpg">'), 'https://i.pinimg.com/736x/a.jpg');
  assert.equal(sharedLink.ogImage("<meta content='https://i.pinimg.com/b.jpg?x=1&amp;y=2' name='og:image'/>"), 'https://i.pinimg.com/b.jpg?x=1&y=2');
  assert.equal(sharedLink.ogImage('<meta property="og:title" content="x">'), null);
});
