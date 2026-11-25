// npm test
// Checks Already in the edit (PRD sections 7, 8 and 11, ticket T14): which pieces are compared,
// what is flagged, and what the member's answer does. Runs on a throwaway database and photo
// folder, and Claude is replaced by a fake, so it costs nothing and needs no network.

const { test, before, after, beforeEach } = require('node:test');
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
const { now, iso } = require('../src/lib/today');
const pieceDetails = require('../src/lib/piece-details');
const pieceQueue = require('../src/jobs/piece-queue');
const lookalikes = require('../src/lib/lookalikes');
const allowance = require('../src/lib/allowance');

// --- The fakes ---

const JACKET = { name: 'olive quilted jacket', kind: 'jacket', colours: ['olive'], pattern: 'plain', material: 'nylon', warmth: 'warm', formality: 'casual' };
// What Claude reads in the next photos, in order; then JACKET.
let nextDetails = [];
pieceDetails.remote.claude = async () => nextDetails.shift() ?? JACKET;

// What Claude answers when asked to compare. `asked` keeps every question's lines of details.
let answerSame = () => [];
let compareFails = false;
let asked = [];
lookalikes.remote.claude = async ({ prompt, schema }) => {
  const lines = prompt.filter((block) => block.type === 'text' && block.text.startsWith('Piece ')).map((block) => block.text);
  const images = prompt.filter((block) => block.type === 'image');
  const numbers = schema.properties.same.items.properties.piece.enum;
  asked.push({ lines, images: images.length, numbers });
  assert.deepEqual(numbers, lines.map((_, i) => String(i + 1)), 'Claude can only name the pieces it is shown');
  if (compareFails) throw new Error('Claude is busy');
  return { same: answerSame(lines) };
};
// "the piece whose name is ..." as Claude would answer it.
const named = (name, certainty = 'high') => (lines) =>
  lines.flatMap((line, i) => (line.toLowerCase().includes(`: ${name.toLowerCase()}.`) ? [{ piece: String(i + 1), certainty }] : []));

beforeEach(() => {
  nextDetails = [];
  answerSame = () => [];
  compareFails = false;
  asked = [];
});

// --- Helpers ---

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
      .run(`alike${memberCount}@example.test`, at, at).lastInsertRowid
  );
  const token = makeToken();
  db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, hashToken(token), at, at);
  require('../src/lib/occasions').proposeFor(id);
  return { id, token };
}

async function picture(colour = '#6B6B35') {
  return (await sharp({ create: { width: 300, height: 400, channels: 3, background: colour } }).jpeg().toBuffer()).toString('base64');
}

async function cutout(colour = '#6B6B35') {
  return (await sharp({ create: { width: 300, height: 400, channels: 4, background: colour } }).png().toBuffer()).toString('base64');
}

// Sends a photo as the app does, and waits until Claude's stand-ins have read and compared it.
async function addPhoto(token, details = JACKET) {
  nextDetails.push(details);
  const res = await call('POST', '/me/pieces', { token, body: { photo: await picture(), cutout: await cutout() } });
  await pieceQueue.idle();
  return res.body.piece.id;
}

const DETAILS = { name: 'Olive quilted jacket', kind: 'jacket', colours: ['olive'], pattern: 'plain', material: 'nylon', warmth: 'warm', formality: 'casual', seasons: [], occasions: [], status: 'confirmed' };

async function confirm(token, id, over = {}) {
  return call('PUT', `/me/pieces/${id}`, { token, body: { ...DETAILS, ...over } });
}

// A piece in the edit, with real photo files.
async function inEdit(token, details = JACKET, over = {}) {
  const id = await addPhoto(token, details);
  await confirm(token, id, { ...details, name: details.name[0].toUpperCase() + details.name.slice(1), ...over });
  return id;
}

const row = (id) => db.prepare('SELECT * FROM pieces WHERE id = ?').get(id);
const queue = async (token) => (await call('GET', '/me/pieces?status=pending', { token })).body.pieces;
const exists = (file) => fs.existsSync(path.join(dataDir, file));

// --- What is compared and flagged ---

test('a new piece that is already in the edit is flagged in the review, and only there', async () => {
  const { id, token } = addMember();
  const old = await inEdit(token);
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token);

  const [piece] = await queue(token);
  assert.equal(piece.id, fresh);
  assert.equal(piece.detailsStatus, 'suggested', 'ready only once it has been compared');
  assert.equal(piece.looksLike.id, old);
  assert.equal(piece.looksLike.name, 'Olive quilted jacket');
  assert.equal(piece.looksLike.waiting, false);
  assert.ok(piece.looksLike.images.thumb.startsWith(`/me/pieces/${old}/thumb`));
  assert.ok(piece.looksLike.images.cutout);

  assert.equal((await call('GET', `/me/pieces/${old}`, { token })).body.piece.looksLike, null, 'the one in the edit asks nothing');
  assert.equal(db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ?`).pluck().get(id), 2, 'one AI action per piece, compared or not');
});

test('nothing to compare with: Claude is not asked', async () => {
  const { token } = addMember();
  await inEdit(token, { ...JACKET, name: 'black loafers', kind: 'loafers', colours: ['black'] });
  asked = [];
  await addPhoto(token);
  assert.equal(asked.length, 0, 'shoes are another chapter');
  assert.equal((await queue(token))[0].looksLike, null);
});

test("only the member's own pieces are compared, in the same chapter, whatever their colour", async () => {
  const other = addMember();
  await inEdit(other.token, { ...JACKET, name: 'someone else jacket' });
  const { token } = addMember();
  await inEdit(token, { ...JACKET, name: 'grey coat', kind: 'coat', colours: ['grey'] });
  await inEdit(token, { ...JACKET, name: 'olive shirt', kind: 'shirt' });
  asked = [];
  await addPhoto(token);
  assert.equal(asked.length, 1);
  assert.equal(asked[0].lines.length, 1);
  assert.match(asked[0].lines[0], /Grey coat/);
  assert.equal(asked[0].images, 2, 'its picture and the new one');
});

test('at most 12 are compared, the most alike first: the same kind before the same colour', async () => {
  const { token } = addMember();
  for (let i = 1; i <= 13; i++) await inEdit(token, { ...JACKET, name: `black coat ${i}`, kind: 'coat', colours: ['black'], material: 'wool' });
  await inEdit(token, { ...JACKET, name: 'olive coat', kind: 'coat', material: 'wool' });
  await inEdit(token, { ...JACKET, name: 'black jacket', colours: ['black'], material: 'wool' });
  asked = [];
  await addPhoto(token);
  assert.equal(asked[0].lines.length, 12);
  assert.match(asked[0].lines[0], /Black jacket/, 'another colour, the same kind');
  assert.match(asked[0].lines[1], /Olive coat/);
});

test('only sure ones are flagged, the surest first, up to three, one at a time', async () => {
  const { token } = addMember();
  const ids = {};
  for (const name of ['one', 'two', 'three', 'four', 'five']) ids[name] = await inEdit(token, { ...JACKET, name: `jacket ${name}` });
  answerSame = (lines) =>
    ['one', 'two', 'three', 'four', 'five'].flatMap((name) =>
      named(`Jacket ${name}`, { one: 'low', two: 'medium', three: 'medium', four: 'high', five: 'medium' }[name])(lines)
    );
  const fresh = await addPhoto(token);
  assert.equal(db.prepare('SELECT COUNT(*) FROM piece_lookalikes WHERE piece_id = ?').pluck().get(fresh), 3);

  let piece = (await queue(token))[0];
  assert.equal(piece.looksLike.id, ids.four, 'the surest first');
  const seen = [piece.looksLike.id];
  while (piece.looksLike) {
    piece = (await call('POST', `/me/pieces/${fresh}/different`, { token, body: { piece: piece.looksLike.id } })).body.piece;
    if (piece.looksLike) seen.push(piece.looksLike.id);
  }
  assert.equal(seen.length, 3);
  assert.ok(!seen.includes(ids.one), 'low is not flagged');
});

test('an answer that names a piece twice, or one it was not shown, is kept out', () => {
  const answer = { same: [{ piece: '9', certainty: 'high' }, { piece: '1', certainty: 'medium' }, { piece: '1', certainty: 'high' }, { piece: '2', certainty: 'sure' }, {}] };
  assert.deepEqual(lookalikes.checked(answer, ['1', '2']), [{ number: '1', certainty: 'medium' }]);
  assert.deepEqual(lookalikes.checked(null, ['1']), []);
  assert.deepEqual(lookalikes.checked({ same: 'none' }, ['1']), []);
});

test('when Claude cannot compare, or the allowance is used up, there is no flag and the piece still waits', async () => {
  const { id, token } = addMember();
  await inEdit(token);
  answerSame = named('Olive quilted jacket');
  compareFails = true;
  await addPhoto(token);
  let [piece] = await queue(token);
  assert.equal(piece.detailsStatus, 'suggested');
  assert.equal(piece.looksLike, null);
  assert.equal((await confirm(token, piece.id)).status, 200);

  compareFails = false;
  asked = [];
  const limit = allowance.allowance();
  allowance.setAllowance(allowance.usedThisMonth(id));
  await addPhoto(token);
  allowance.setAllowance(limit);
  [piece] = await queue(token);
  assert.equal(piece.detailsStatus, 'not read');
  assert.equal(piece.looksLike, null);
  assert.equal(asked.length, 0);
});

test('two photos of the same piece in one batch: the newer one is flagged', async () => {
  const { token } = addMember();
  answerSame = named('olive quilted jacket');
  nextDetails = [JACKET, JACKET];
  const body = { photo: await picture(), cutout: await cutout() };
  const [first, second] = await Promise.all([call('POST', '/me/pieces', { token, body }), call('POST', '/me/pieces', { token, body })]);
  await pieceQueue.idle();
  const ids = [first.body.piece.id, second.body.piece.id].sort((a, b) => a - b);

  const pieces = await queue(token);
  assert.deepEqual(pieces.map((p) => [p.id, p.looksLike?.id ?? null, p.looksLike?.waiting ?? null]), [[ids[0], null, null], [ids[1], ids[0], true]]);

  // The same: the first stays, still to review.
  const res = await call('POST', `/me/pieces/${ids[1]}/same`, { token, body: { piece: ids[0], photo: 'new' } });
  assert.equal(res.body.piece.id, ids[0]);
  assert.equal(res.body.piece.status, 'pending');
  assert.deepEqual((await queue(token)).map((p) => p.id), [ids[0]]);
});

// --- Same ---

test('the same piece, keeping the old photo: the new piece and its photos go, nothing else changes', async () => {
  const { id, token } = addMember();
  const old = await inEdit(token);
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token);
  const [before, gone] = [row(old), row(fresh)];
  const progress = (await call('GET', '/me/wardrobe', { token })).body.progress.pieces;

  const res = await call('POST', `/me/pieces/${fresh}/same`, { token, body: { piece: old, photo: 'old' } });
  assert.equal(res.status, 200);
  assert.deepEqual(row(old), before);
  assert.equal(row(fresh), undefined);
  for (const file of [gone.original_path, gone.cutout_path, gone.thumb_path]) assert.equal(exists(file), false);
  for (const file of [before.original_path, before.cutout_path, before.thumb_path]) assert.equal(exists(file), true);
  assert.equal(res.body.progress.pieces, progress, 'the count stays the same');
  assert.equal(db.prepare('SELECT COUNT(*) FROM piece_lookalikes WHERE user_id = ?').pluck().get(id), 0);
});

test('the same piece, using the new photo: its details, seasons, occasions and looks stay; the old photo goes', async () => {
  const { id, token } = addMember();
  const occasion = db.prepare('SELECT id FROM occasions WHERE user_id = ? LIMIT 1').pluck().get(id);
  const old = await inEdit(token, JACKET, { occasions: [occasion], brand: 'Arket', notes: 'From Rotterdam.', fits: false });
  const look = db.prepare(`INSERT INTO looks (user_id, number, source, created_at) VALUES (?, 1, 'built', ?)`).run(id, iso(now())).lastInsertRowid;
  db.prepare(`INSERT INTO look_pieces (user_id, look_id, piece_id, slot) VALUES (?, ?, ?, 'outer layer')`).run(id, look, old);
  // A store's picture, as after Bought.
  db.prepare(`UPDATE pieces SET store_photo = 'Arket' WHERE id = ?`).run(old);
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token, { ...JACKET, name: 'green jacket', colours: ['green'] });
  const [before, replacement] = [row(old), row(fresh)];
  const oldUrl = (await call('GET', `/me/pieces/${old}`, { token })).body.piece.images.thumb;

  const res = await call('POST', `/me/pieces/${fresh}/same`, { token, body: { piece: old, photo: 'new' } });
  assert.equal(res.status, 200);
  const now_ = row(old);
  assert.deepEqual([now_.original_path, now_.cutout_path, now_.thumb_path], [replacement.original_path, replacement.cutout_path, replacement.thumb_path]);
  assert.equal(now_.store_photo, null, '"Photo from Arket." goes');
  assert.notEqual(res.body.piece.images.thumb, oldUrl, 'a new address, so the iPhone shows the new picture');
  for (const key of ['name', 'kind', 'brand', 'notes', 'fits', 'status', 'confirmed_at']) assert.equal(now_[key], before[key], key);
  assert.deepEqual(res.body.piece.colours, ['olive']);
  assert.deepEqual(res.body.piece.occasions, [occasion]);
  assert.equal(res.body.piece.looks, 1);
  assert.equal(row(fresh), undefined);
  for (const file of [before.original_path, before.cutout_path, before.thumb_path]) assert.equal(exists(file), false);
  for (const file of [replacement.original_path, replacement.cutout_path, replacement.thumb_path]) assert.equal(exists(file), true);
});

// --- Different, and what is refused ---

test('a different piece is remembered: it is confirmed as its own, and not asked about again', async () => {
  const { id, token } = addMember();
  const old = await inEdit(token);
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token);
  const res = await call('POST', `/me/pieces/${fresh}/different`, { token, body: { piece: old } });
  assert.equal(res.body.piece.looksLike, null);
  assert.equal((await queue(token))[0].looksLike, null);
  assert.deepEqual(lookalikes.candidatesFor(row(fresh)), [], 'those two are not compared again');
  assert.equal((await confirm(token, fresh)).status, 200);
  assert.equal(db.prepare(`SELECT COUNT(*) FROM pieces WHERE user_id = ? AND status = 'confirmed'`).pluck().get(id), 2);
  assert.equal((await call('POST', `/me/pieces/${fresh}/same`, { token, body: { piece: old, photo: 'new' } })).status, 400, 'answered already');
});

test("only a flag that exists, only the member's own pieces, and only a clear choice of photo", async () => {
  const { token } = addMember();
  const other = addMember();
  const old = await inEdit(token);
  const unrelated = await inEdit(token, { ...JACKET, name: 'black loafers', kind: 'loafers' });
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token);
  const theirs = await inEdit(other.token);

  const same = (body, as = token, id = fresh) => call('POST', `/me/pieces/${id}/same`, { token: as, body });
  assert.equal((await same({ piece: old })).status, 400);
  assert.equal((await same({ piece: old, photo: 'best' })).status, 400);
  assert.equal((await same({ piece: unrelated, photo: 'old' })).status, 400, 'Caro did not ask about this one');
  assert.equal((await same({ piece: theirs, photo: 'old' })).status, 404);
  assert.equal((await same({ photo: 'old' })).status, 404);
  assert.equal((await same({ piece: old, photo: 'old' }, other.token)).status, 404);
  assert.equal((await call('POST', `/me/pieces/${fresh}/different`, { token: other.token, body: { piece: old } })).status, 404);
  assert.equal((await call('POST', `/me/pieces/${fresh}/same`, { body: { piece: old, photo: 'old' } })).status, 401);
  assert.equal((await same({ piece: fresh, photo: 'old' }, token, old)).status, 400, 'a piece in the edit is never joined into another');
  for (const id of [old, unrelated, fresh, theirs]) assert.ok(row(id), 'a refusal changes nothing');
  assert.equal((await queue(token))[0].looksLike.id, old);
});

test('an older app, which does not know the note, can still confirm; the flag then goes quiet', async () => {
  const { token } = addMember();
  const old = await inEdit(token);
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token);
  assert.equal((await confirm(token, fresh)).status, 200);
  assert.equal((await call('GET', `/me/pieces/${fresh}`, { token })).body.piece.looksLike, null);
  assert.equal((await call('POST', `/me/pieces/${fresh}/same`, { token, body: { piece: old, photo: 'old' } })).status, 400);
});

test('removing either piece removes the flag', async () => {
  const { id, token } = addMember();
  const old = await inEdit(token);
  answerSame = named('Olive quilted jacket');
  const fresh = await addPhoto(token);
  assert.equal((await queue(token))[0].looksLike.id, old);
  await call('DELETE', `/me/pieces/${old}`, { token });
  assert.equal((await queue(token))[0].looksLike, null);
  await call('DELETE', `/me/pieces/${fresh}`, { token });
  assert.equal(db.prepare('SELECT COUNT(*) FROM piece_lookalikes WHERE user_id = ?').pluck().get(id), 0);
});

test('a piece removed or confirmed while Claude compares it is left alone', async () => {
  const { token } = addMember();
  const old = await inEdit(token);
  const plain = lookalikes.remote.claude;
  let during = null;
  lookalikes.remote.claude = async (question) => {
    await during();
    return plain(question);
  };
  answerSame = named('Olive quilted jacket');
  try {
    let id;
    during = () => call('DELETE', `/me/pieces/${id}`, { token });
    nextDetails.push(JACKET);
    id = (await call('POST', '/me/pieces', { token, body: { photo: await picture(), cutout: await cutout() } })).body.piece.id;
    await pieceQueue.idle();
    assert.equal(row(id), undefined);

    during = () => confirm(token, id);
    nextDetails.push(JACKET);
    id = (await call('POST', '/me/pieces', { token, body: { photo: await picture(), cutout: await cutout() } })).body.piece.id;
    await pieceQueue.idle();
    assert.equal(row(id).status, 'confirmed');
    assert.equal(db.prepare('SELECT COUNT(*) FROM piece_lookalikes WHERE piece_id = ?').pluck().get(id), 0, 'two pieces in the edit are not flagged');
    assert.ok(row(old));
  } finally {
    lookalikes.remote.claude = plain;
  }
});
