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

const LIGHT_NEEDS_C = 20;

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

// After the member changed the number of seasons: every piece with a warmth gets new seasons.
// The member confirms them in one batch in T6 (PRD section 8).
function proposeForAllPieces(userId) {
  const rule = seasonsByWarmth(userId);
  const pieces = db.prepare('SELECT id, warmth FROM pieces WHERE user_id = ? AND warmth IS NOT NULL').all(userId);
  for (const piece of pieces) proposeForPiece(userId, piece.id, piece.warmth, rule);
}

module.exports = { seasonsByWarmth, proposeForPiece, proposeForAllPieces };
