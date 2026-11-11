// A member's set-up: the answers from onboarding steps 1 to 5, which Settings changes later.
// Every function takes the member's own id and touches only their rows.

const db = require('../db');
const { now, iso } = require('./today');
const { memberJSON } = require('./members');
const occasions = require('./occasions');

const DATE_ORDERS = ['day month', 'month day'];
const SIZE_SYSTEMS = ['EU', 'US', 'UK', 'AU'];

// The year counts as confirmed once step 3 was saved: later in onboarding, or set up.
function yearConfirmed(member) {
  return member.status === 'active' || member.onboarding_step >= 4;
}

function seasonsFor(userId) {
  const seasons = db.prepare('SELECT id, name FROM seasons WHERE user_id = ? ORDER BY position').all(userId);
  const months = db.prepare('SELECT month, season_id FROM season_months WHERE user_id = ? ORDER BY month').all(userId);
  return seasons.map((s) => ({ id: s.id, name: s.name, months: months.filter((m) => m.season_id === s.id).map((m) => m.month) }));
}

function storeJSON(store) {
  return {
    id: store.id,
    name: store.name,
    domain: store.domain,
    countryUrl: store.country_url,
    sellsOnline: store.sells_online === 1,
    country: store.country,
  };
}

function storesFor(userId) {
  return db.prepare('SELECT * FROM stores WHERE user_id = ? ORDER BY position').all(userId).map(storeJSON);
}

// Who invited this member, from their accepted invitation. Null for the admin.
function invitedBy(member) {
  return (
    db
      .prepare(
        `SELECT users.name FROM invitations JOIN users ON users.id = invitations.invited_by
         WHERE invitations.email = ? AND invitations.status = 'accepted'
         ORDER BY invitations.sent_at DESC LIMIT 1`
      )
      .pluck()
      .get(member.email) ?? null
  );
}

// Everything the five steps and Settings show, in one answer. Every save sends it back,
// so the app always shows what the server holds.
function setupJSON(userId) {
  const member = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  const city = member.city_id ? db.prepare('SELECT * FROM cities WHERE id = ?').get(member.city_id) : null;

  return {
    member: memberJSON(member),
    invitedBy: invitedBy(member),
    place: member.city
      ? {
          cityId: member.city_id,
          city: member.city,
          region: city?.region ?? null,
          country: member.country,
          currency: member.currency,
          dateOrder: member.date_order,
          sizeSystem: member.size_system,
        }
      : null,
    yearConfirmed: yearConfirmed(member),
    seasons: seasonsFor(userId),
    sections: {
      womens: member.shops_womens === 1,
      mens: member.shops_mens === 1,
      unisex: member.shops_unisex === 1,
    },
    stores: storesFor(userId),
    occasions: occasions.occasionsFor(userId),
    proposedOccasions: occasions.proposalsJSON(),
    // The server's today (DEV_TODAY in development), for the "Now:" line and date examples.
    today: iso(now()).slice(0, 10),
  };
}

// Saves a year. With the same number of seasons, the seasons are updated in place, so a
// renamed season keeps its pieces and looks. With another number, they are replaced.
// T5: when that happens with pieces, propose their new seasons from their warmth (PRD section 8).
function saveSeasons(userId, seasons) {
  const existing = db.prepare('SELECT id FROM seasons WHERE user_id = ? ORDER BY position').pluck().all(userId);
  db.prepare('DELETE FROM season_months WHERE user_id = ?').run(userId);

  let ids;
  if (existing.length === seasons.length) {
    // Names are unique per member, so swapping two names needs a stop in between.
    const rename = db.prepare('UPDATE seasons SET name = ? WHERE id = ? AND user_id = ?');
    existing.forEach((id) => rename.run(`season ${id} renaming`, id, userId));
    existing.forEach((id, i) => rename.run(seasons[i].name, id, userId));
    ids = existing;
  } else {
    db.prepare('DELETE FROM seasons WHERE user_id = ?').run(userId);
    const add = db.prepare('INSERT INTO seasons (user_id, name, position) VALUES (?, ?, ?)');
    ids = seasons.map((s, i) => add.run(userId, s.name, i + 1).lastInsertRowid);
  }

  const addMonth = db.prepare('INSERT INTO season_months (user_id, month, season_id) VALUES (?, ?, ?)');
  seasons.forEach((season, i) => season.months.forEach((month) => addMonth.run(userId, month, ids[i])));
}

function clearSeasons(userId) {
  db.prepare('DELETE FROM seasons WHERE user_id = ?').run(userId);
}

function savePlace(userId, city, { currency, dateOrder, sizeSystem }) {
  db.prepare(
    `UPDATE users SET city_id = ?, city = ?, country = ?, currency = ?, date_order = ?, size_system = ?
     WHERE id = ?`
  ).run(city.id, city.name, city.country, currency, dateOrder, sizeSystem, userId);
}

module.exports = {
  DATE_ORDERS,
  SIZE_SYSTEMS,
  yearConfirmed,
  seasonsFor,
  storesFor,
  setupJSON,
  saveSeasons,
  clearSeasons,
  savePlace,
};
