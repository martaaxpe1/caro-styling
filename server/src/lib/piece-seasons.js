// Which of the member's seasons a piece is for, proposed from its warmth (PRD sections 8 and 9).
// A rule in code, not the AI. Warmth means the same everywhere; the member's year decides the rest.
//
// Each season's typical high is the average of its months' typical highs (city_weather).
// - Four seasons: light is the warmest season and the one before it (spring and summer),
//   warm is the coldest season and the one before it (autumn and winter), medium is all four.
// - Two seasons: light and medium are both, but light skips a season whose typical high is
//   under 20 °C; warm is the cooler one.
// - No seasons: nothing to propose.
// So a linen shirt is spring and summer in the Netherlands, and both seasons in Miami.
// It works in the southern hemisphere and with renamed seasons or moved months, because it
// only looks at temperatures and the order of the months.
//
// The member checks the seasons in the review queue and can change them.

const db = require('../db');
const { now } = require('./today');

const LIGHT_NEEDS_C = 20;

// The season holding today's month (DEV_TODAY in development), as { id, name }, or null with no
// seasons. The edit's dateline ("The autumn edit") and the default chapter filter (PRD section 9).
function currentSeason(userId) {
  const month = now().getUTCMonth() + 1;
  return (
    db
      .prepare(
        `SELECT seasons.id, seasons.name FROM season_months JOIN seasons ON seasons.id = season_months.season_id
         WHERE season_months.user_id = ? AND season_months.month = ?`
      )
      .get(userId, month) ?? null
  );
}


function seasonsWithHighs(userId) {
  const member = db.prepare('SELECT city_id FROM users WHERE id = ?').get(userId);
  const highs = new Map(
    db.prepare('SELECT month, high_c FROM city_weather WHERE city_id = ?').all(member?.city_id ?? -1).map((row) => [row.month, row.high_c])
  );
  const seasons = db.prepare('SELECT id FROM seasons WHERE user_id = ? ORDER BY position').all(userId);
  const months = db.prepare('SELECT month FROM season_months WHERE season_id = ? ORDER BY month');

  return seasons.map((season) => {
    const list = months.pluck().all(season.id);
    const known = list.filter((month) => highs.has(month));
    return {
      id: season.id,
      months: list,
      high: known.length ? known.reduce((sum, month) => sum + highs.get(month), 0) / known.length : null,
    };
  });
}

// The seasons in the order of the year: each one comes right after the season that holds the
// month before its first month. Spring, summer, autumn, winter; in the south too.
function inYearOrder(seasons) {
  const seasonOfMonth = new Map();
  seasons.forEach((season) => season.months.forEach((month) => seasonOfMonth.set(month, season)));
  const firstMonth = (season) => season.months.find((month) => seasonOfMonth.get(month === 1 ? 12 : month - 1) !== season);
  return [...seasons].sort((a, b) => (firstMonth(a) ?? 0) - (firstMonth(b) ?? 0));
}

// { light: [season ids], medium: [...], warm: [...] } for one member. Empty lists when the member
// has no seasons, or when their city's typical weather is not known.
function seasonsByWarmth(userId) {
  const seasons = seasonsWithHighs(userId);
  const empty = { light: [], medium: [], warm: [] };
  if (seasons.length === 0 || seasons.some((season) => season.high === null)) return empty;

  const ids = (list) => list.map((season) => season.id);
  const medium = ids(seasons);

  if (seasons.length === 2) {
    const [cooler, warmer] = [...seasons].sort((a, b) => a.high - b.high);
    return {
      light: ids(seasons.filter((season) => season === warmer || season.high >= LIGHT_NEEDS_C)),
      medium,
      warm: [cooler.id],
    };
  }

  // Four (or any other number): the warmest and coldest seasons, each with the season before it.
  const year = inYearOrder(seasons);
  const before = (season) => year[(year.indexOf(season) + year.length - 1) % year.length];
  const warmest = seasons.reduce((a, b) => (b.high > a.high ? b : a));
  const coldest = seasons.reduce((a, b) => (b.high < a.high ? b : a));
  const inPositionOrder = (list) => seasons.filter((season) => list.includes(season)).map((season) => season.id);
  return {
    light: inPositionOrder([warmest, before(warmest)]),
    medium,
    warm: inPositionOrder([coldest, before(coldest)]),
  };
}

// Gives one piece the seasons its warmth proposes, replacing the ones it had.
function proposeForPiece(userId, pieceId, warmth, rule = seasonsByWarmth(userId)) {
  db.prepare('DELETE FROM piece_seasons WHERE piece_id = ? AND user_id = ?').run(pieceId, userId);
  const add = db.prepare('INSERT INTO piece_seasons (user_id, piece_id, season_id) VALUES (?, ?, ?)');
  for (const seasonId of rule[warmth] ?? []) add.run(userId, pieceId, seasonId);
}

// After the member changed the number of seasons: every piece with a warmth gets new seasons
// (a piece with no warmth lost its old ones with the old year). Pieces already in the edit are
// marked to check, so the member confirms them in one batch (PRD section 8). Pieces still in the
// review queue are checked there anyway. With no seasons now, there is nothing to check.
function proposeForAllPieces(userId) {
  const rule = seasonsByWarmth(userId);
  const hasSeasons = Boolean(db.prepare('SELECT 1 FROM seasons WHERE user_id = ? LIMIT 1').get(userId));
  const pieces = db.prepare('SELECT id, warmth, status FROM pieces WHERE user_id = ?').all(userId);
  const mark = db.prepare('UPDATE pieces SET seasons_to_check = ? WHERE id = ? AND user_id = ?');
  for (const piece of pieces) {
    if (piece.warmth) proposeForPiece(userId, piece.id, piece.warmth, rule);
    mark.run(hasSeasons && piece.status !== 'pending' ? 1 : 0, piece.id, userId);
  }
}

// The groups of the batch check, by warmth: the pieces marked to check, and the seasons the
// rule proposes for each group ("none" for pieces with no warmth: no proposal).
const GROUPS = ['light', 'medium', 'warm', 'none'];

function piecesToCheck(userId) {
  return db
    .prepare(`SELECT * FROM pieces WHERE user_id = ? AND seasons_to_check = 1 AND status IN ('confirmed', 'maybe') ORDER BY id`)
    .all(userId);
}

// Confirms the batch: { light: [season ids], medium: [...], warm: [...], none: [...] }.
// Each marked piece gets the seasons of its warmth's group. A group that was not sent is left
// as it is, still to check (for example a piece marked while the member was looking).
// The season ids must already be checked as the member's own.
const confirmBatch = db.transaction((userId, groups) => {
  const clear = db.prepare('UPDATE pieces SET seasons_to_check = 0 WHERE id = ? AND user_id = ?');
  const remove = db.prepare('DELETE FROM piece_seasons WHERE piece_id = ? AND user_id = ?');
  const add = db.prepare('INSERT INTO piece_seasons (user_id, piece_id, season_id) VALUES (?, ?, ?)');
  let confirmed = 0;
  for (const piece of piecesToCheck(userId)) {
    const seasons = groups[piece.warmth ?? 'none'];
    if (!seasons) continue;
    remove.run(piece.id, userId);
    for (const seasonId of seasons) add.run(userId, piece.id, seasonId);
    clear.run(piece.id, userId);
    confirmed += 1;
  }
  return confirmed;
});

module.exports = { GROUPS, currentSeason, seasonsByWarmth, proposeForPiece, proposeForAllPieces, piecesToCheck, confirmBatch };
