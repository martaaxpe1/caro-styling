// npm run seed
// Fills an empty database with Marta as admin and, on this Mac only, a pending invitation
// for a test Sara. If Marta is already there, it adds nothing and prints what is there.
// Marta's email comes from ADMIN_EMAIL in server/.env, so it never goes into Git.

const path = require('path');
const db = require('../src/db');
const { now, iso, devToday } = require('../src/lib/today');
const { databaseFile } = require('../src/lib/paths');

const isProduction = process.env.NODE_ENV === 'production';
const DAY = 24 * 60 * 60 * 1000;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const ADMIN = {
  name: 'Marta',
  city: 'Rotterdam',
  country: 'NL',
  currency: 'EUR',
  dateOrder: 'day month',
  sizeSystem: 'EU',
  shopsWomens: 1,
  shopsMens: 0,
  shopsUnisex: 1,
};

// Four seasons in the Netherlands, as the year rule proposes them (PRD section 9).
const SEASONS = [
  { name: 'Spring', months: [3, 4, 5] },
  { name: 'Summer', months: [6, 7, 8] },
  { name: 'Autumn', months: [9, 10, 11] },
  { name: 'Winter', months: [12, 1, 2] },
];

// Marta's example stores, with the Dutch shops the T1 spike found (docs/SPIKE.md, test 4).
const STORES = [
  { name: 'Arket', domain: 'arket.com', countryUrl: 'https://www.arket.com/en-nl/' },
  { name: 'COS', domain: 'cos.com', countryUrl: 'https://www.cos.com/en-nl/' },
  { name: 'Uniqlo', domain: 'uniqlo.com', countryUrl: 'https://www.uniqlo.com/nl/nl/' },
  { name: 'Zara', domain: 'zara.com', countryUrl: 'https://www.zara.com/nl/' },
  { name: 'Ganni', domain: 'ganni.com', countryUrl: 'https://www.ganni.com/en-nl/' },
  { name: 'Bimba y Lola', domain: 'bimbaylola.com', countryUrl: 'https://www.bimbaylola.com/nl_en/' },
  { name: 'Samsøe Samsøe', domain: 'samsoe.com', countryUrl: 'https://www.samsoe.com/en-NL/' },
];

// Rotterdam, as Open-Meteo's city search finds it (T4). Its typical weather is looked up the
// first time Marta opens Your year in Settings.
const ROTTERDAM = {
  id: 2747891,
  name: 'Rotterdam',
  region: 'South Holland',
  country: 'NL',
  latitude: 51.9225,
  longitude: 4.47917,
  timezone: 'Europe/Amsterdam',
};

const TEST_INVITATION = { name: 'Sara', email: 'sara@example.com' };

function readAdminEmail() {
  const email = (process.env.ADMIN_EMAIL || '').trim().toLowerCase();
  if (!email.includes('@')) {
    console.error('Add your email to server/.env first, as a line like ADMIN_EMAIL=you@example.com');
    console.error('The seed makes that email the admin account.');
    process.exit(1);
  }
  return email;
}

// Marta has done onboarding steps 1 to 5 (where she lives, her year, her stores),
// so she starts at step 6, building her wardrobe, with Looks and Get the look still locked.
const addAdmin = db.transaction((email) => {
  const createdAt = iso(now());

  db.prepare(
    `INSERT INTO cities (id, name, region, country, latitude, longitude, timezone, created_at)
     VALUES (@id, @name, @region, @country, @latitude, @longitude, @timezone, @createdAt)
     ON CONFLICT (id) DO NOTHING`
  ).run({ ...ROTTERDAM, createdAt });

  const { lastInsertRowid: userId } = db
    .prepare(
      `INSERT INTO users (email, name, role, status, onboarding_step, city_id, city, country, currency,
         date_order, size_system, shops_womens, shops_mens, shops_unisex, created_at)
       VALUES (@email, @name, 'admin', 'active', 6, @cityId, @city, @country, @currency,
         @dateOrder, @sizeSystem, @shopsWomens, @shopsMens, @shopsUnisex, @createdAt)`
    )
    .run({ ...ADMIN, cityId: ROTTERDAM.id, email, createdAt });

  const addSeason = db.prepare('INSERT INTO seasons (user_id, name, position) VALUES (?, ?, ?)');
  const addMonth = db.prepare('INSERT INTO season_months (user_id, month, season_id) VALUES (?, ?, ?)');
  SEASONS.forEach((season, index) => {
    const { lastInsertRowid: seasonId } = addSeason.run(userId, season.name, index + 1);
    season.months.forEach((month) => addMonth.run(userId, month, seasonId));
  });

  const addStore = db.prepare(
    `INSERT INTO stores (user_id, name, domain, country_url, sells_online, country, position, created_at)
     VALUES (?, ?, ?, ?, 1, ?, ?, ?)`
  );
  STORES.forEach((store, index) => {
    addStore.run(userId, store.name, store.domain, store.countryUrl, ADMIN.country, index + 1, createdAt);
  });

  return userId;
});

// Only on this Mac: online, invitations are real and sent from the admin area (T3).
function addTestInvitation(adminId) {
  const exists = db.prepare('SELECT 1 FROM invitations WHERE email = ?').get(TEST_INVITATION.email);
  if (exists) return;

  const sent = now();
  db.prepare(
    `INSERT INTO invitations (name, email, invited_by, status, sent_at, expires_at)
     VALUES (?, ?, ?, 'pending', ?, ?)`
  ).run(TEST_INVITATION.name, TEST_INVITATION.email, adminId, iso(sent), iso(new Date(sent.getTime() + 14 * DAY)));
}

// What gets printed

function day(date) {
  const d = new Date(date);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

// The months of one season as a range, like "Dec to Feb".
function monthRange(months) {
  const inSeason = new Set(months);
  const first = months.find((m) => !inSeason.has(m === 1 ? 12 : m - 1));
  const last = months.find((m) => !inSeason.has(m === 12 ? 1 : m + 1));
  if (first === undefined) return 'all year';
  return `${MONTHS[first - 1]} to ${MONTHS[last - 1]}`;
}

function printAdmin(email) {
  const admin = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
  const country = new Intl.DisplayNames(['en'], { type: 'region' }).of(admin.country);

  const seasons = db
    .prepare('SELECT * FROM seasons WHERE user_id = ? ORDER BY position')
    .all(admin.id)
    .map((season) => {
      const months = db.prepare('SELECT month FROM season_months WHERE season_id = ?').pluck().all(season.id);
      return `${season.name} (${monthRange(months)})`;
    });

  const sections = [
    admin.shops_womens && "women's",
    admin.shops_mens && "men's",
    admin.shops_unisex && 'unisex',
  ].filter(Boolean);

  const stores = db.prepare('SELECT name FROM stores WHERE user_id = ? ORDER BY position').pluck().all(admin.id);

  console.log('\nAdmin');
  console.log(`  ${admin.name}, ${admin.email}`);
  console.log(`  ${admin.city}, ${country}, ${admin.currency}`);
  console.log(`  Role ${admin.role}, status ${admin.status}, onboarding step ${admin.onboarding_step}, ${admin.unlocked_at ? 'unlocked' : 'Looks locked'}`);
  console.log(`  Seasons: ${seasons.join(', ') || 'none'}`);
  console.log(`  Shops in: ${sections.join(', ') || 'not chosen yet'}`);
  console.log(`  Stores: ${stores.join(', ') || 'none'}`);
}

function printInvitations() {
  const invitations = db.prepare('SELECT * FROM invitations ORDER BY id').all();
  console.log('\nInvitations');
  if (invitations.length === 0) console.log('  none');
  for (const invitation of invitations) {
    console.log(
      `  ${invitation.name}, ${invitation.email}, ${invitation.status}, sent ${day(invitation.sent_at)}, expires ${day(invitation.expires_at)}`
    );
  }
}

// The seed itself

const email = readAdminEmail();

console.log(`Database: ${path.relative(process.cwd(), databaseFile) || databaseFile}`);
console.log(`Today: ${day(now())}${devToday ? ' (pretend, from DEV_TODAY)' : ''}`);

const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
const adminId = existing ? existing.id : addAdmin(email);
if (existing) console.log('\nAlready seeded, nothing added. To start over: npm run reset-dev');

if (!isProduction) addTestInvitation(adminId);

printAdmin(email);
printInvitations();

// Closing folds SQLite's working files (caro.db-wal, caro.db-shm) back into caro.db.
db.close();
