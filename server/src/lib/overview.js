// The wardrobe overview (screen S7, PRD sections 7 and 8): what the member has, as facts.
// Counts by chapter, main colour, season and occasion; once there is a look, the pieces in no
// look yet and the occasions with fewer than three looks. Never advice, never what to buy.
// Only the member's own counted pieces (confirmed or maybe).

const db = require('../db');
const lists = require('./lists');
const { COUNTED, looksCount } = require('./wardrobe');
const { imageUrl } = require('./pieces');

function overviewJSON(userId) {
  const total = db.prepare(`SELECT COUNT(*) FROM pieces WHERE user_id = ? AND ${COUNTED}`).pluck().get(userId);

  // Every chapter, with 0 where there is nothing: an empty chapter is a fact too.
  const byChapter = new Map(
    db
      .prepare(
        `SELECT kinds.chapter, COUNT(*) AS count FROM pieces JOIN kinds ON kinds.name = pieces.kind
         WHERE pieces.user_id = ? AND ${COUNTED} GROUP BY kinds.chapter`
      )
      .all(userId)
      .map((row) => [row.chapter, row.count])
  );
  const chapters = lists.load().chapters.map((c) => ({ name: c.name, number: c.number, count: byChapter.get(c.name) ?? 0 }));

  // By main colour (position 1), so the numbers add up to the whole wardrobe. In list order.
  const byColour = new Map(
    db
      .prepare(
        `SELECT piece_colours.colour, COUNT(*) AS count FROM piece_colours JOIN pieces ON pieces.id = piece_colours.piece_id
         WHERE pieces.user_id = ? AND ${COUNTED} AND piece_colours.position = 1 GROUP BY piece_colours.colour`
      )
      .all(userId)
      .map((row) => [row.colour, row.count])
  );
  const colours = lists
    .load()
    .colours.filter((name) => byColour.has(name))
    .map((name) => ({ name, count: byColour.get(name) }));

  const seasons = db
    .prepare(
      `SELECT seasons.id, seasons.name,
         (SELECT COUNT(*) FROM piece_seasons JOIN pieces ON pieces.id = piece_seasons.piece_id
          WHERE piece_seasons.season_id = seasons.id AND ${COUNTED}) AS count
       FROM seasons WHERE seasons.user_id = ? ORDER BY seasons.position`
    )
    .all(userId);
  const noSeason = db
    .prepare(
      `SELECT COUNT(*) FROM pieces WHERE user_id = ? AND ${COUNTED}
       AND NOT EXISTS (SELECT 1 FROM piece_seasons WHERE piece_seasons.piece_id = pieces.id)`
    )
    .pluck()
    .get(userId);

  const occasions = db
    .prepare(
      `SELECT occasions.id, occasions.name,
         (SELECT COUNT(*) FROM piece_occasions JOIN pieces ON pieces.id = piece_occasions.piece_id
          WHERE piece_occasions.occasion_id = occasions.id AND ${COUNTED}) AS count,
         (SELECT COUNT(*) FROM look_occasions WHERE look_occasions.occasion_id = occasions.id) AS looks
       FROM occasions WHERE occasions.user_id = ? ORDER BY occasions.position`
    )
    .all(userId);
  const noOccasion = db
    .prepare(
      `SELECT COUNT(*) FROM pieces WHERE user_id = ? AND ${COUNTED}
       AND NOT EXISTS (SELECT 1 FROM piece_occasions WHERE piece_occasions.piece_id = pieces.id)`
    )
    .pluck()
    .get(userId);

  // The looks facts wait for the first look: before it, every piece is in no look.
  const looks = looksCount(userId);
  let notInALook = null;
  let occasionsFewLooks = null;
  if (looks > 0) {
    const pieces = db
      .prepare(
        `SELECT * FROM pieces WHERE user_id = ? AND ${COUNTED}
         AND NOT EXISTS (SELECT 1 FROM look_pieces WHERE look_pieces.piece_id = pieces.id)
         ORDER BY id DESC`
      )
      .all(userId);
    notInALook = {
      count: pieces.length,
      pieces: pieces.slice(0, 8).map((p) => ({ id: p.id, name: p.name, thumb: imageUrl(p, 'thumb'), hasCutout: Boolean(p.cutout_path) })),
    };
    occasionsFewLooks = occasions.filter((o) => o.looks < 3).map((o) => ({ id: o.id, name: o.name, looks: o.looks }));
  }

  return {
    pieces: total,
    chapters,
    colours,
    seasons: seasons.map(({ id, name, count }) => ({ id, name, count })),
    noSeason,
    occasions: occasions.map(({ id, name, count }) => ({ id, name, count })),
    noOccasion,
    looks,
    notInALook,
    occasionsFewLooks,
  };
}

module.exports = { overviewJSON };
