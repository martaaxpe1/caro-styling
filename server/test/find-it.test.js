// npm test
// Checks Find it and To find (PRD sections 7, 8, 10 and 11, ticket T11): marking a piece as key
// searches each of the member's stores that sells online in their country, all at once, only
// products in their currency on that store's site, up to three per store; the member's own
// search words; keep and discard; Search
// again keeps the kept ones; Bought adds the piece to the edit with no AI action; the monthly
// AI allowance; the admin's AI totals; and that one member never reaches another's To find.
// Claude and the stores are replaced by stand-ins, so nothing outside is called.

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
const storeSearch = require('../src/lib/store-search');
const queue = require('../src/jobs/search-queue');

// The stand-in for Claude's store search.
let nextProducts = () => [];
let searches = [];
// It gets one store; the test's products are handed to the store whose site they are on, so
// a product on another site is what Claude might wrongly return for this store.
storeSearch.remote.claude = async (member, store, piece) => {
  searches.push({ member: member.id, store: store.domain, piece });
  const answer = nextProducts(member, store);
  if (answer instanceof Error) throw answer;
  return { products: answer.filter((p) => !p.url.includes('.cos.com') && !p.url.includes('.zara.com') ? store.domain === 'cos.com' : p.url.includes(`.${store.domain}`)) };
};
storeSearch.remote.previewImage = async () => 'https://images.example.test/preview.jpg';

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
function addMember({ country = 'NL', currency = 'EUR', role = 'member' } = {}) {
  memberCount += 1;
  const at = iso(now());
  const id = Number(
    db
      .prepare(
        `INSERT INTO users (email, name, role, status, onboarding_step, country, currency, shops_womens, unlocked_at, created_at)
         VALUES (?, 'Test', ?, 'active', 6, ?, ?, 1, ?, ?)`
      )
      .run(`finder${memberCount}@example.test`, role, country, currency, at, at).lastInsertRowid
  );
  const token = makeToken();
  db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, hashToken(token), at, at);
  const addStore = db.prepare(
    `INSERT INTO stores (user_id, name, domain, country_url, sells_online, country, position, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const shop = country.toLowerCase();
  addStore.run(id, 'COS', 'cos.com', `https://www.cos.com/en-${shop}/`, 1, country, 1, at);
  addStore.run(id, 'Zara', 'zara.com', `https://www.zara.com/${shop}/`, 1, country, 2, at);
  addStore.run(id, 'Arket', 'arket.com', null, 0, country, 3, at);
  return { id, token };
}

// An inspiration with one missing piece, a black leather bag, at pin 1.
function addInspiration(userId) {
  const at = iso(now());
  const inspirationId = Number(
    db
      .prepare(`INSERT INTO inspirations (user_id, photo_path, thumb_path, status, created_at) VALUES (?, 'photos/x/abc-photo.jpg', 'photos/x/abc-thumb.webp', 'ready', ?)`)
      .run(userId, at).lastInsertRowid
  );
  db.prepare(
    `INSERT INTO inspiration_pieces (user_id, inspiration_id, number, description, kind, colour, shape, match) VALUES (?, ?, 1, 'Black leather shoulder bag', 'bag', 'black', 'small, chain strap', 'missing')`
  ).run(userId, inspirationId);
  return inspirationId;
}

const product = (over) => ({ name: 'Leather shoulder bag', price: 89, currency: 'EUR', url: 'https://www.cos.com/en-nl/bag-1.html', image_url: 'https://images.cos.com/bag-1.jpg', ...over });

async function markKey(member, inspirationId) {
  const res = await call('PUT', `/me/inspirations/${inspirationId}/pieces/1`, { token: member.token, body: { key: true } });
  assert.equal(res.status, 200);
  await queue.idle();
  const home = await call('GET', '/me/inspirations', { token: member.token });
  return home.body.toFind[0];
}

async function photo() {
  return (await sharp({ create: { width: 600, height: 600, channels: 3, background: '#EFE7DB' } }).jpeg().toBuffer()).toString('base64');
}

test('Mark as key searches each store, in their currency, on that store, up to three per store', async () => {
  const marta = addMember();
  const inspirationId = addInspiration(marta.id);
  searches = [];
  nextProducts = () => [
    product({}),
    product({ name: 'In dollars', currency: 'USD', url: 'https://www.cos.com/en-us/bag-2.html' }),
    product({ name: 'Another shop', url: 'https://www.example.com/bag.html' }),
    product({ name: 'Not https', url: 'http://www.zara.com/nl/bag.html' }),
    product({ name: 'No price', price: 0, url: 'https://www.zara.com/nl/bag-0.html' }),
    product({ name: 'Zara bag', price: 49.95, url: 'https://www.zara.com/nl/bag-3.html', image_url: '' }),
    product({ name: 'Twice', url: 'https://www.cos.com/en-nl/bag-1.html' }),
    ...[4, 5, 6, 7].map((n) => product({ name: `Bag ${n}`, url: `https://www.cos.com/en-nl/bag-${n}.html` })),
  ];
  const row = await markKey(marta, inspirationId);
  assert.deepEqual(searches.map((s) => s.store).sort(), ['cos.com', 'zara.com'], 'Arket has no online shop, so it is not searched');
  assert.match(searches[0].piece, /Black leather shoulder bag, small, chain strap/);
  assert.equal(row.searchStatus, 'done');
  assert.equal(row.found, 4);

  const page = await call('GET', `/me/to-find/${row.id}`, { token: marta.token });
  assert.equal(page.status, 200);
  const names = page.body.toFind.results.map((r) => r.name);
  assert.deepEqual(names, ['Leather shoulder bag', 'Bag 4', 'Bag 5', 'Zara bag'], 'three from COS, one from Zara, in the order of the stores');
  assert.ok(page.body.toFind.results.every((r) => r.currency === 'EUR'));
  assert.equal(page.body.toFind.results[3].priceCents, 4995);
  assert.match(page.body.toFind.results[3].image, /^\/me\/to-find\/\d+\/results\/\d+\/image$/);
  const zara = db.prepare(`SELECT image_url FROM store_results WHERE name = 'Zara bag'`).pluck().get();
  assert.equal(zara, 'https://images.example.test/preview.jpg', 'no image from Claude: the page preview');
  assert.equal(page.body.toFind.results[0].store, 'COS');
  assert.equal(page.body.toFind.notSearched.length, 1);
  assert.match(page.body.toFind.notSearched[0], /Arket has no online shop in the Netherlands/);

  const usage = db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'store search'`).pluck().get(marta.id);
  assert.equal(usage, 1, 'one search of every store is one AI action');
  assert.equal(page.body.toFind.searchWords, 'Black leather shoulder bag, small, chain strap');
  assert.equal(page.body.toFind.progress, null, 'no progress once done');
});

test('One store failing still shows the others; the member can search with their own words', async () => {
  const member = addMember();
  const inspirationId = addInspiration(member.id);
  nextProducts = (m, store) => (store.domain === 'zara.com' ? new Error('Claude took too long to answer.') : []);
  const row = await markKey(member, inspirationId);
  assert.equal(row.searchStatus, 'done', 'COS answered: nothing found there');
  assert.equal(row.found, 0);

  searches = [];
  nextProducts = () => [product({ name: 'Crossbody bag' })];
  const again = await call('POST', `/me/to-find/${row.id}/search`, { token: member.token, body: { words: '  black   crossbody bag ' } });
  assert.equal(again.status, 200);
  assert.equal(again.body.toFind.searchWords, 'black crossbody bag');
  assert.equal(again.body.toFind.ownWords, true);
  assert.equal(again.body.toFind.progress.length, 2, 'each store, while searching');
  await queue.idle();
  assert.ok(searches.every((s) => s.piece === 'black crossbody bag'));
  const page = (await call('GET', `/me/to-find/${row.id}`, { token: member.token })).body.toFind;
  assert.deepEqual(page.results.map((r) => r.name), ['Crossbody bag']);

  // Empty words: back to Caro's description.
  await call('POST', `/me/to-find/${row.id}/search`, { token: member.token, body: { words: '' } });
  await queue.idle();
  const back = (await call('GET', `/me/to-find/${row.id}`, { token: member.token })).body.toFind;
  assert.equal(back.ownWords, false);
  assert.match(back.searchWords, /^Black leather shoulder bag/);
});

test('Nothing found is a valid answer; a failed search can be tried again', async () => {
  const member = addMember();
  const inspirationId = addInspiration(member.id);
  nextProducts = () => new Error('Claude could not be reached.');
  const row = await markKey(member, inspirationId);
  assert.equal(row.searchStatus, 'failed');
  assert.match(row.searchMessage, /could not search/);

  nextProducts = () => [];
  const again = await call('POST', `/me/to-find/${row.id}/search`, { token: member.token });
  assert.equal(again.status, 200);
  assert.equal(again.body.toFind.searchStatus, 'searching');
  await queue.idle();
  const page = await call('GET', `/me/to-find/${row.id}`, { token: member.token });
  assert.equal(page.body.toFind.searchStatus, 'done');
  assert.deepEqual(page.body.toFind.results, []);
  assert.ok(page.body.toFind.searchedAt);
});

test('Keep and discard; Search again keeps the kept ones and replaces the rest', async () => {
  const member = addMember();
  const inspirationId = addInspiration(member.id);
  nextProducts = () => [product({}), product({ name: 'Second', url: 'https://www.cos.com/en-nl/bag-2.html' }), product({ name: 'Third', url: 'https://www.zara.com/nl/bag-3.html' })];
  const row = await markKey(member, inspirationId);
  const page = (await call('GET', `/me/to-find/${row.id}`, { token: member.token })).body.toFind;
  const [first, second] = page.results;

  const kept = await call('PUT', `/me/to-find/${row.id}/results/${second.id}`, { token: member.token, body: { decision: 'kept' } });
  assert.equal(kept.body.toFind.results[0].name, 'Second', 'kept ones come first');
  const discarded = await call('PUT', `/me/to-find/${row.id}/results/${first.id}`, { token: member.token, body: { decision: 'discarded' } });
  assert.deepEqual(discarded.body.toFind.results.map((r) => r.name), ['Second', 'Third']);

  nextProducts = () => [product({}), product({ name: 'Fourth', url: 'https://www.zara.com/nl/bag-4.html' })];
  await call('POST', `/me/to-find/${row.id}/search`, { token: member.token });
  await queue.idle();
  const after = (await call('GET', `/me/to-find/${row.id}`, { token: member.token })).body.toFind;
  assert.deepEqual(after.results.map((r) => [r.name, r.decision]), [['Second', 'kept'], ['Fourth', null]], 'a discarded product found again stays discarded');

  const home = await call('GET', '/me/inspirations', { token: member.token });
  assert.equal(home.body.toFind[0].kept, 1);
});

test('Bought adds the piece to the edit with the store picture, fills the version, and leaves To find', async () => {
  const member = addMember();
  const inspirationId = addInspiration(member.id);
  nextProducts = () => [product({})];
  const row = await markKey(member, inspirationId);
  const result = (await call('GET', `/me/to-find/${row.id}`, { token: member.token })).body.toFind.results[0];
  const before = db.prepare('SELECT COUNT(*) FROM ai_usage WHERE user_id = ?').pluck().get(member.id);

  const bought = await call('POST', `/me/to-find/${row.id}/bought`, { token: member.token, body: { result: result.id, photo: await photo(), cutout: null } });
  assert.equal(bought.status, 201);
  const piece = bought.body.piece;
  assert.equal(piece.status, 'confirmed');
  assert.equal(piece.kind, 'bag');
  assert.deepEqual(piece.colours, ['black']);
  assert.equal(piece.brand, 'COS');
  assert.equal(piece.storePhoto, 'COS');
  assert.equal(db.prepare('SELECT COUNT(*) FROM ai_usage WHERE user_id = ?').pluck().get(member.id), before, 'no AI action');
  assert.equal(db.prepare('SELECT price_cents FROM pieces WHERE id = ?').pluck().get(piece.id), 8900);

  const version = await call('GET', `/me/inspirations/${inspirationId}`, { token: member.token });
  assert.equal(version.body.inspiration.pieces[0].match, 'filled');
  assert.equal(version.body.inspiration.owned, 1);
  const home = await call('GET', '/me/inspirations', { token: member.token });
  assert.equal(home.body.toFind.length, 0);

  const again = await call('POST', `/me/to-find/${row.id}/bought`, { token: member.token, body: { result: result.id, photo: await photo() } });
  assert.equal(again.status, 409);

  // Retake: the member's own photo, and the store's picture note goes.
  const retaken = await call('PUT', `/me/pieces/${piece.id}/photo`, { token: member.token, body: { photo: await photo() } });
  assert.equal(retaken.body.piece.storePhoto, null);
});

test('No store to search: the piece stays key, with the reason', async () => {
  const member = addMember();
  db.prepare('UPDATE stores SET sells_online = 0, country_url = NULL WHERE user_id = ?').run(member.id);
  const inspirationId = addInspiration(member.id);
  searches = [];
  const row = await markKey(member, inspirationId);
  assert.equal(searches.length, 0);
  assert.equal(row.searchStatus, 'failed');
  assert.match(row.searchMessage, /None of your stores/);
});

test('With the allowance used up, nothing asks Claude and the message says when it starts again', async () => {
  const member = addMember();
  const inspirationId = addInspiration(member.id);
  db.prepare('UPDATE settings SET ai_monthly_allowance = 2 WHERE id = 1').run();
  try {
    const at = iso(now());
    db.prepare(`INSERT INTO ai_usage (user_id, action, created_at) VALUES (?, 'piece details', ?), (?, 'inspiration', ?)`).run(member.id, at, member.id, at);
    // Last month's actions do not count.
    db.prepare(`INSERT INTO ai_usage (user_id, action, created_at) VALUES (?, 'inspiration', '2026-09-30T10:00:00Z')`).run(member.id);
    searches = [];
    const row = await markKey(member, inspirationId);
    assert.equal(searches.length, 0);
    assert.equal(row.searchMessage, "You have used this month's 2 AI actions. They start again on 1 November.");

    const again = await call('POST', `/me/to-find/${row.id}/search`, { token: member.token });
    assert.equal(again.status, 429);
    assert.match(again.body.error, /start again on 1 November/);

    const store = await call('POST', '/me/stores/find', { token: member.token, body: { name: 'Toteme' } });
    assert.equal(store.status, 429);
    const inspired = await call('POST', '/me/inspirations', { token: member.token, body: { photo: await photo() } });
    assert.equal(inspired.status, 429);
    const spotted = await call('POST', '/me/looks/spot', { token: member.token, body: { photo: await photo() } });
    assert.equal(spotted.status, 429);
  } finally {
    db.prepare('UPDATE settings SET ai_monthly_allowance = 300 WHERE id = 1').run();
  }
});

test('The admin sees the AI totals and sets the allowance; a member cannot', async () => {
  const admin = addMember({ role: 'admin' });
  const member = addMember();
  const page = await call('GET', '/admin', { token: admin.token });
  assert.equal(page.status, 200);
  assert.equal(page.body.ai.allowance, 300);
  assert.ok(page.body.ai.total >= 1);
  assert.ok(page.body.ai.byAction.some((row) => row.action === 'store search'));

  const set = await call('PUT', '/admin/allowance', { token: admin.token, body: { allowance: 150 } });
  assert.equal(set.body.ai.allowance, 150);
  assert.equal((await call('PUT', '/admin/allowance', { token: admin.token, body: { allowance: -1 } })).status, 400);
  assert.equal((await call('PUT', '/admin/allowance', { token: member.token, body: { allowance: 1000 } })).status, 403);
  await call('PUT', '/admin/allowance', { token: admin.token, body: { allowance: 300 } });
});

test("A member never reaches another member's To find", async () => {
  const one = addMember();
  const other = addMember();
  const inspirationId = addInspiration(one.id);
  nextProducts = () => [product({})];
  const row = await markKey(one, inspirationId);
  const result = (await call('GET', `/me/to-find/${row.id}`, { token: one.token })).body.toFind.results[0];
  assert.equal((await call('GET', `/me/to-find/${row.id}`, { token: other.token })).status, 404);
  assert.equal((await call('POST', `/me/to-find/${row.id}/search`, { token: other.token })).status, 404);
  assert.equal((await call('PUT', `/me/to-find/${row.id}/results/${result.id}`, { token: other.token, body: { decision: 'kept' } })).status, 404);
  assert.equal((await call('POST', `/me/to-find/${row.id}/bought`, { token: other.token, body: { result: result.id, photo: await photo() } })).status, 404);
  assert.equal((await call('GET', `/me/to-find/${row.id}/results/${result.id}/image`, { token: other.token })).status, 404);
});
