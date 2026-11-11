// npm test
// Checks onboarding steps 1 to 5 and Settings against PRD sections 5, 8, 9 and 11.
// Like sign-in.test.js, it runs on a throwaway database. Claude, Open-Meteo and the city
// search are replaced by fakes here, so the tests cost nothing and need no network.

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
const email = require('../src/lib/email');
const places = require('../src/lib/places');
const weather = require('../src/lib/weather');
const stores = require('../src/lib/stores');
const { proposeYear, checkSeasons } = require('../src/lib/year');
const { statusAfterRestore } = require('../src/lib/members');
const { now, iso, DAY } = require('../src/lib/today');

// Official 1991 to 2020 normals, from server/spike/5-year.js.
const NORMALS = {
  miami: {
    high: [24.6, 25.7, 27.0, 28.7, 30.4, 31.8, 32.6, 32.6, 31.7, 29.9, 27.4, 25.7],
    rain: [46, 55, 62, 85, 161, 267, 187, 243, 260, 194, 90, 62],
  },
  amsterdam: {
    high: [6.2, 6.9, 10.1, 14.3, 17.8, 20.3, 22.5, 22.4, 19.2, 14.7, 10.0, 6.9],
    rain: [66.5, 54.7, 51.8, 39.6, 53.9, 64.8, 82.3, 98.6, 84.4, 86.7, 85.3, 81.7],
  },
  buenosAires: {
    high: [30.1, 28.9, 27.0, 23.2, 19.4, 16.4, 15.5, 17.9, 19.7, 22.6, 26.0, 29.0],
    rain: [134.4, 129.3, 120.0, 130.3, 93.5, 61.5, 74.4, 70.3, 80.6, 122.9, 117.6, 122.8],
  },
  // Warm all year with rain spread out: no seasons.
  singapore: {
    high: [30.4, 31.3, 31.9, 32.1, 31.8, 31.4, 30.9, 30.9, 30.9, 31.1, 30.6, 29.9],
    rain: [242, 162, 186, 179, 171, 162, 158, 176, 169, 194, 256, 288],
  },
};

function months({ high, rain }, shift = 0) {
  return high.map((h, i) => ({ month: i + 1, highC: h + shift, rainMm: rain[i] }));
}

// The fake outside world.
const CITIES = {
  4164138: { id: 4164138, name: 'Miami', admin1: 'Florida', country_code: 'US', latitude: 25.77, longitude: -80.19, timezone: 'America/New_York' },
  2759794: { id: 2759794, name: 'Amsterdam', admin1: 'North Holland', country_code: 'NL', latitude: 52.37, longitude: 4.89, timezone: 'Europe/Amsterdam' },
  3435910: { id: 3435910, name: 'Buenos Aires', admin1: 'Buenos Aires F.D.', country_code: 'AR', latitude: -34.61, longitude: -58.38, timezone: 'America/Argentina/Buenos_Aires' },
};
const WEATHER = { 4164138: NORMALS.miami, 2759794: NORMALS.amsterdam, 3435910: NORMALS.buenosAires };

const calls = { claudeWeather: 0, openMeteo: 0 };
let openMeteoDown = false;
let openMeteoShift = 0; // degrees Open-Meteo runs cold by, in the fake

places.remote.search = async (name) => Object.values(CITIES).filter((c) => c.name.toLowerCase().startsWith(name.toLowerCase()));
places.remote.byId = async (id) => CITIES[id] || null;
weather.remote.claude = async (city) => {
  calls.claudeWeather++;
  return months(WEATHER[city.id]);
};
weather.remote.openMeteo = async (city) => {
  calls.openMeteo++;
  if (openMeteoDown) throw new Error('down');
  return months(WEATHER[city.id], -openMeteoShift);
};
stores.remote.claude = async (name) => {
  const known = {
    zara: { found: true, official_name: 'Zara', domain: 'zara.com', website: 'https://www.zara.com/us/', sells_online: 'yes', evidence: '' },
    arket: { found: true, official_name: 'Arket', domain: 'arket.com', website: '', sells_online: 'no', evidence: '' },
    unsure: { found: true, official_name: 'Unsure', domain: 'unsure.com', website: 'https://www.unsure.com/', sells_online: 'not sure', evidence: '' },
  };
  return known[name.toLowerCase()] || { found: false, official_name: '', domain: '', website: '', sells_online: 'not sure', evidence: '' };
};

const codes = {};
email.sendSignInCode = (to, code) => {
  codes[to] = code;
};
email.sendInvitation = () => {};

let server;
let base;

before(async () => {
  const at = iso(now());
  const { lastInsertRowid: adminId } = db
    .prepare(`INSERT INTO users (email, name, role, status, onboarding_step, created_at) VALUES ('admin@example.test', 'Marta', 'admin', 'active', 6, ?)`)
    .run(at);
  const invite = db.prepare(`INSERT INTO invitations (name, email, invited_by, status, sent_at, expires_at) VALUES (?, ?, ?, 'pending', ?, ?)`);
  for (const [name, address] of [['Sara', 'sara@example.test'], ['Ana', 'ana@example.test'], ['Bo', 'bo@example.test']]) {
    invite.run(name, address, adminId, at, iso(new Date(now().getTime() + 14 * DAY)));
  }

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

async function signIn(address) {
  await call('POST', '/auth/code', { body: { email: address } });
  const verified = await call('POST', '/auth/verify', { body: { email: address, code: codes[address] } });
  assert.equal(verified.status, 200, verified.body.error);
  return verified.body.token;
}

const MIAMI_PLACE = { cityId: 4164138, currency: 'USD', dateOrder: 'month day', sizeSystem: 'US' };

// Walks a new member through steps 1 to 3 in Miami, with the proposed two seasons.
async function upToStores(token) {
  await call('PUT', '/me/name', { token, body: { name: 'Test' } });
  await call('PUT', '/me/place', { token, body: MIAMI_PLACE });
  const year = await call('GET', '/me/year', { token });
  await call('PUT', '/me/year', { token, body: { seasons: year.body.options.two } });
}

// The rule

test('the rule proposes two seasons for Miami: hot and rainy May to October, mild and dry November to April', () => {
  const year = proposeYear(months(NORMALS.miami), 25.77);
  assert.equal(year.suggested, 'two');
  assert.deepEqual(year.options.two, [
    { name: 'Hot and rainy', months: [5, 6, 7, 8, 9, 10] },
    { name: 'Mild and dry', months: [11, 12, 1, 2, 3, 4] },
  ]);
});

test('the rule proposes four seasons for Amsterdam, and for Buenos Aires shifted by six months', () => {
  const amsterdam = proposeYear(months(NORMALS.amsterdam), 52.37);
  assert.equal(amsterdam.suggested, 'four');
  assert.deepEqual(amsterdam.options.four[0], { name: 'Spring', months: [3, 4, 5] });
  assert.deepEqual(amsterdam.options.four[3], { name: 'Winter', months: [12, 1, 2] });

  const buenosAires = proposeYear(months(NORMALS.buenosAires), -34.61);
  assert.equal(buenosAires.suggested, 'four');
  assert.deepEqual(buenosAires.options.four[0], { name: 'Spring', months: [9, 10, 11] });
  assert.deepEqual(buenosAires.options.four[1], { name: 'Summer', months: [12, 1, 2] });
});

test('the rule proposes no seasons where it is warm all year and the rain is spread out, and still offers two', () => {
  const year = proposeYear(months(NORMALS.singapore), 1.29);
  assert.equal(year.suggested, 'none');
  assert.equal(year.options.two.length, 2);
  assert.equal(checkSeasons(year.options.two).error, undefined);
});

test('a year must be four, two or none seasons, with every month in exactly one', () => {
  assert.ok(checkSeasons([{ name: 'All', months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] }]).error);
  assert.ok(checkSeasons([{ name: 'A', months: [1, 2, 3] }, { name: 'B', months: [4, 5, 6] }]).error, 'months missing');
  assert.ok(checkSeasons([{ name: 'A', months: [1, 2, 3, 4, 5, 6, 7] }, { name: 'B', months: [7, 8, 9, 10, 11, 12] }]).error, 'July twice');
  assert.ok(checkSeasons([{ name: 'Same', months: [1, 2, 3, 4, 5, 6] }, { name: 'same', months: [7, 8, 9, 10, 11, 12] }]).error);
  assert.ok(checkSeasons([{ name: 'A', months: [] }, { name: 'B', months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] }]).error);
  assert.deepEqual(checkSeasons([]), { seasons: [] });
});

// Onboarding, as the PRD's "Done when" for T4

let saraToken;
let firstStoreId;

test('Sara starts at step 1, invited by Marta, with her name from the invitation', async () => {
  saraToken = await signIn('sara@example.test');
  const setup = await call('GET', '/me/setup', { token: saraToken });
  assert.equal(setup.body.member.onboardingStep, 1);
  assert.equal(setup.body.member.name, 'Sara');
  assert.equal(setup.body.invitedBy, 'Marta');
  assert.equal(setup.body.place, null);
  assert.equal(setup.body.today, '2026-10-30');
});

test('step 1 saves her name and moves her to step 2', async () => {
  const saved = await call('PUT', '/me/name', { token: saraToken, body: { name: '  Sara  ' } });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.member.name, 'Sara');
  assert.equal(saved.body.member.onboardingStep, 2);
  assert.equal((await call('PUT', '/me/name', { token: saraToken, body: { name: ' ' } })).status, 400);
});

test('step 2 finds Miami and saves it with US formats', async () => {
  const found = await call('GET', '/places?q=Miami, Florida', { token: saraToken });
  assert.equal(found.status, 200);
  assert.deepEqual(found.body.cities[0], { id: 4164138, name: 'Miami', region: 'Florida', country: 'US' });
  assert.equal((await call('GET', '/places?q=Miami')).status, 401, 'city search is for signed-in members only');

  const saved = await call('PUT', '/me/place', { token: saraToken, body: MIAMI_PLACE });
  assert.equal(saved.status, 200, saved.body.error);
  assert.deepEqual(saved.body.place, {
    cityId: 4164138,
    city: 'Miami',
    region: 'Florida',
    country: 'US',
    currency: 'USD',
    dateOrder: 'month day',
    sizeSystem: 'US',
  });
  assert.equal(saved.body.member.onboardingStep, 3);
});

test('step 3 proposes two seasons from the weather, looked up once and kept', async () => {
  const year = await call('GET', '/me/year', { token: saraToken });
  assert.equal(year.status, 200, year.body.error);
  assert.equal(year.body.suggested, 'two');
  assert.equal(year.body.months.length, 12);
  assert.equal(year.body.months[6].highC, 32.6);
  assert.equal(year.body.saved, null);
  assert.equal(year.body.today, '2026-10-30');

  await call('GET', '/me/year', { token: saraToken });
  assert.equal(calls.claudeWeather, 1, 'Claude is asked once per city');
  const sara = db.prepare(`SELECT id FROM users WHERE email = 'sara@example.test'`).pluck().get();
  const used = db.prepare(`SELECT action FROM ai_usage WHERE user_id = ?`).pluck().all(sara);
  assert.deepEqual(used, ['your year']);
});

test('step 3 saves the year she confirmed, with a month moved and a season renamed', async () => {
  const seasons = [
    { name: 'Rainy season', months: [5, 6, 7, 8, 9, 10, 11] },
    { name: 'Mild and dry', months: [12, 1, 2, 3, 4] },
  ];
  const saved = await call('PUT', '/me/year', { token: saraToken, body: { seasons } });
  assert.equal(saved.status, 200, saved.body.error);
  assert.deepEqual(
    saved.body.seasons.map(({ name, months }) => ({ name, months: [...months].sort((a, b) => a - b) })),
    [
      { name: 'Rainy season', months: [5, 6, 7, 8, 9, 10, 11] },
      { name: 'Mild and dry', months: [1, 2, 3, 4, 12] },
    ]
  );
  assert.equal(saved.body.member.onboardingStep, 4);

  // Back to the proposal's names: the same two seasons, updated in place.
  const ids = saved.body.seasons.map((s) => s.id);
  const again = await call('PUT', '/me/year', {
    token: saraToken,
    body: { seasons: [{ name: 'Hot and rainy', months: [5, 6, 7, 8, 9, 10] }, { name: 'Mild and dry', months: [11, 12, 1, 2, 3, 4] }] },
  });
  assert.deepEqual(again.body.seasons.map((s) => s.id), ids);
  assert.equal((await call('GET', '/me/year', { token: saraToken })).body.saved[0].name, 'Hot and rainy');
});

test('step 4 finds a store site for her country, adds it, and says when there is no online shop', async () => {
  const zara = await call('POST', '/me/stores/find', { token: saraToken, body: { name: 'zara' } });
  assert.equal(zara.status, 200);
  assert.deepEqual(zara.body.store, {
    found: true,
    name: 'Zara',
    domain: 'zara.com',
    countryUrl: 'https://www.zara.com/us/',
    sellsOnline: true,
    country: 'US',
  });
  const added = await call('POST', '/me/stores', { token: saraToken, body: zara.body.store });
  assert.equal(added.status, 201, added.body.error);
  firstStoreId = added.body.stores[0].id;

  const arket = await call('POST', '/me/stores/find', { token: saraToken, body: { name: 'Arket' } });
  assert.equal(arket.body.store.sellsOnline, false);
  assert.equal(arket.body.store.domain, 'arket.com');
  const both = await call('POST', '/me/stores', { token: saraToken, body: arket.body.store });
  assert.deepEqual(
    both.body.stores.map((s) => [s.name, s.sellsOnline, s.country]),
    [
      ['Zara', true, 'US'],
      ['Arket', false, 'US'],
    ]
  );

  const unsure = await call('POST', '/me/stores/find', { token: saraToken, body: { name: 'Unsure' } });
  assert.equal(unsure.body.store.sellsOnline, false, 'not sure counts as no online shop');
  assert.equal(unsure.body.store.countryUrl, null);

  const unknown = await call('POST', '/me/stores/find', { token: saraToken, body: { name: 'Nowhere shop' } });
  assert.deepEqual(unknown.body.store, { found: false, name: 'Nowhere shop' });

  const twice = await call('POST', '/me/stores', { token: saraToken, body: zara.body.store });
  assert.equal(twice.status, 409);
  assert.equal(twice.body.error, 'Zara is already in your stores.');

  const sara = db.prepare(`SELECT id FROM users WHERE email = 'sara@example.test'`).pluck().get();
  const lookUps = db.prepare(`SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND action = 'store website'`).pluck().get(sara);
  assert.equal(lookUps, 4, 'every look-up counts as an AI action');
});

test('a store site must be on the store domain, over https', async () => {
  const wrong = await call('POST', '/me/stores', {
    token: saraToken,
    body: { name: 'Cos', domain: 'cos.com', countryUrl: 'https://evil.example/cos', sellsOnline: true },
  });
  assert.equal(wrong.status, 400);
});

test('closing the app and opening it again resumes at step 4, with both stores', async () => {
  const me = await call('GET', '/me', { token: saraToken });
  assert.equal(me.body.member.status, 'onboarding');
  assert.equal(me.body.member.onboardingStep, 4);
  const setup = await call('GET', '/me/setup', { token: saraToken });
  assert.equal(setup.body.stores.length, 2);
  assert.equal(setup.body.yearConfirmed, true);
});

test('another member cannot touch her stores', async () => {
  const anaToken = await signIn('ana@example.test');
  const removed = await call('DELETE', `/me/stores/${firstStoreId}`, { token: anaToken });
  assert.equal(removed.status, 404);
  const changed = await call('PUT', `/me/stores/${firstStoreId}`, {
    token: anaToken,
    body: { domain: 'zara.com', countryUrl: 'https://www.zara.com/nl/', sellsOnline: true },
  });
  assert.equal(changed.status, 404);
  const setup = await call('GET', '/me/setup', { token: saraToken });
  assert.equal(setup.body.stores.length, 2);
});

test('step 4 keeps the sections as they are tapped, and needs one to continue', async () => {
  const none = await call('POST', '/me/onboarding/stores-done', { token: saraToken });
  assert.equal(none.status, 400);
  assert.equal(none.body.error, 'Choose at least one section.');

  const womens = await call('PUT', '/me/sections', { token: saraToken, body: { womens: true } });
  assert.equal(womens.status, 200);
  assert.deepEqual(womens.body.sections, { womens: true, mens: false, unisex: false });
  assert.equal(womens.body.member.onboardingStep, 4, 'a tap saves, it does not move on');

  const done = await call('POST', '/me/onboarding/stores-done', { token: saraToken });
  assert.equal(done.status, 200);
  assert.equal(done.body.member.onboardingStep, 5);
});

test('a new member starts with Caro\'s four occasions, explained', async () => {
  const setup = await call('GET', '/me/setup', { token: saraToken });
  assert.deepEqual(
    setup.body.occasions.map((o) => o.name),
    ['Office', 'Working from home', 'Night out', 'Day out']
  );
  assert.equal(setup.body.occasions[0].description, 'Workdays with colleagues or clients.');
  assert.equal(setup.body.proposedOccasions.length, 4);
});

test('occasions follow the rules: one to eight, a name each, no repeats, only your own', async () => {
  const mine = (await call('GET', '/me/setup', { token: saraToken })).body.occasions;
  const save = (list, token = saraToken) => call('PUT', '/me/occasions', { token, body: { occasions: list } });

  assert.equal((await save([])).body.error, 'Keep at least one occasion.');
  const nine = Array.from({ length: 9 }, (_, i) => ({ name: `Occasion ${i + 1}` }));
  assert.equal((await save(nine)).body.error, 'Up to eight occasions.');
  assert.equal((await save([{ name: 'Travel' }, { name: 'travel' }])).body.error, 'Give each occasion its own name.');
  assert.equal((await save([{ name: 'x'.repeat(31) }])).body.error, 'Keep occasion names to 30 letters.');

  // Another member cannot rename or take Sara's occasions.
  const anaToken = await signIn('ana@example.test');
  const stolen = await save([{ id: mine[0].id, name: 'Mine now' }], anaToken);
  assert.equal(stolen.status, 400);

  const after = (await call('GET', '/me/setup', { token: saraToken })).body;
  assert.deepEqual(after.occasions, mine, 'nothing changed');
  assert.equal(after.member.onboardingStep, 5, 'a refused save does not move on');
});

test('step 5 keeps, renames, removes and adds occasions, and finishes set-up', async () => {
  const [office, home, night] = (await call('GET', '/me/setup', { token: saraToken })).body.occasions;
  const done = await call('PUT', '/me/occasions', {
    token: saraToken,
    body: { occasions: [{ id: office.id, name: 'Studio' }, home, night, { name: 'Travel' }] },
  });
  assert.equal(done.status, 200, done.body.error);
  assert.deepEqual(
    done.body.occasions.map((o) => o.name),
    ['Studio', 'Working from home', 'Night out', 'Travel']
  );
  assert.equal(done.body.occasions[0].id, office.id, 'a rename keeps the occasion');
  assert.equal(done.body.occasions[0].description, null, 'a renamed proposal loses its line');
  assert.equal(done.body.occasions[3].description, null);

  assert.equal(done.body.member.status, 'active');
  assert.equal(done.body.member.onboardingStep, 6);
  const sara = db.prepare(`SELECT * FROM users WHERE email = 'sara@example.test'`).get();
  assert.equal(statusAfterRestore(sara), 'active');
});

test('in Settings, two occasions can swap names and a removed proposal can come back', async () => {
  const [studio, home, night, travel] = (await call('GET', '/me/setup', { token: saraToken })).body.occasions;
  const swapped = await call('PUT', '/me/occasions', {
    token: saraToken,
    body: { occasions: [{ id: studio.id, name: 'Travel' }, home, night, { id: travel.id, name: 'Studio' }, { name: 'day out' }] },
  });
  assert.equal(swapped.status, 200, swapped.body.error);
  assert.deepEqual(
    swapped.body.occasions.map((o) => [o.id ?? 'new', o.name]),
    [[studio.id, 'Travel'], [home.id, 'Working from home'], [night.id, 'Night out'], [travel.id, 'Studio'], [swapped.body.occasions[4].id, 'day out']]
  );
  assert.equal(swapped.body.occasions[4].description, 'Weekends, errands and lunches with friends.');
  assert.equal(swapped.body.member.status, 'active');
});

test('a step cannot be skipped by calling the server directly', async () => {
  const boToken = await signIn('bo@example.test');
  await call('PUT', '/me/sections', { token: boToken, body: { unisex: true } });
  await call('POST', '/me/onboarding/stores-done', { token: boToken });
  await call('PUT', '/me/occasions', { token: boToken, body: { occasions: [{ name: 'Office' }] } });
  const me = await call('GET', '/me', { token: boToken });
  assert.equal(me.body.member.status, 'onboarding');
  assert.equal(me.body.member.onboardingStep, 1);
});

test('step 4 can be skipped for now', async () => {
  const anaToken = await signIn('ana@example.test');
  await upToStores(anaToken);
  const skipped = await call('POST', '/me/onboarding/skip-stores', { token: anaToken });
  assert.equal(skipped.body.member.onboardingStep, 5);
  assert.deepEqual(skipped.body.sections, { womens: false, mens: false, unisex: false });
});

test('choosing another city in onboarding goes back to step 3 for a new year', async () => {
  const anaToken = await signIn('ana@example.test');
  const moved = await call('PUT', '/me/place', {
    token: anaToken,
    body: { cityId: 2759794, currency: 'EUR', dateOrder: 'day month', sizeSystem: 'EU' },
  });
  assert.equal(moved.body.member.onboardingStep, 3);
  assert.deepEqual(moved.body.seasons, []);
  assert.equal(moved.body.yearConfirmed, false);
  const year = await call('GET', '/me/year', { token: anaToken });
  assert.equal(year.body.suggested, 'four');
});

// Settings

test('in Settings, a new city is saved only together with its new year', async () => {
  const alone = await call('PUT', '/me/place', {
    token: saraToken,
    body: { cityId: 3435910, currency: 'ARS', dateOrder: 'day month', sizeSystem: 'EU' },
  });
  assert.equal(alone.status, 400);
  assert.equal((await call('GET', '/me/setup', { token: saraToken })).body.place.city, 'Miami', 'nothing changed');

  const proposal = await call('GET', '/me/year?cityId=3435910', { token: saraToken });
  assert.equal(proposal.body.suggested, 'four');
  assert.equal(proposal.body.saved, null);

  const moved = await call('PUT', '/me/place', {
    token: saraToken,
    body: { cityId: 3435910, currency: 'ARS', dateOrder: 'day month', sizeSystem: 'EU', seasons: proposal.body.options.four },
  });
  assert.equal(moved.status, 200, moved.body.error);
  assert.equal(moved.body.place.city, 'Buenos Aires');
  assert.equal(moved.body.seasons.length, 4);
  assert.equal(moved.body.member.status, 'active');
  // Her stores keep the sites found for the US until she confirms new ones.
  assert.deepEqual(moved.body.stores.map((s) => s.country), ['US', 'US']);
});

test('a store gets the site for her new country when she confirms it', async () => {
  const updated = await call('PUT', `/me/stores/${firstStoreId}`, {
    token: saraToken,
    body: { domain: 'zara.com', countryUrl: 'https://www.zara.com/ar/', sellsOnline: true },
  });
  assert.equal(updated.status, 200, updated.body.error);
  assert.equal(updated.body.stores[0].country, 'AR');
  const removed = await call('DELETE', `/me/stores/${firstStoreId}`, { token: saraToken });
  assert.deepEqual(removed.body.stores.map((s) => s.name), ['Arket']);
});

// The weather sources

test('Open-Meteo numbers are used when Claude differs by more than 3 °C in a month', async () => {
  db.prepare('DELETE FROM city_weather WHERE city_id = 2759794').run();
  openMeteoShift = 3.5;
  const months = await weather.typicalWeather(await places.cityById(2759794), 1);
  assert.equal(months[6].highC, 22.5 - 3.5);
  assert.equal(db.prepare('SELECT weather_source FROM cities WHERE id = 2759794').pluck().get(), 'open-meteo');
  openMeteoShift = 0;
});

test("Claude's numbers are kept when Open-Meteo is down, and checked the next time", async () => {
  db.prepare('DELETE FROM city_weather WHERE city_id = 2759794').run();
  openMeteoDown = true;
  const first = await weather.typicalWeather(await places.cityById(2759794), 1);
  assert.equal(first[6].highC, 22.5);
  assert.equal(db.prepare('SELECT weather_checked FROM cities WHERE id = 2759794').pluck().get(), 0);

  openMeteoDown = false;
  const claudeCalls = calls.claudeWeather;
  await weather.typicalWeather(await places.cityById(2759794), 1);
  assert.equal(calls.claudeWeather, claudeCalls, 'Claude is not asked again');
  assert.equal(db.prepare('SELECT weather_checked FROM cities WHERE id = 2759794').pluck().get(), 1);
});
