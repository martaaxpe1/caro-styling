// A member's looks as the app sees them, and the checks before one is saved (PRD sections 6 to 8).
// Every function takes the member's own id and touches only their rows.
//
// The member styles every look. Nothing here proposes, ranks or completes a look: the server
// only checks that the pieces the member chose are theirs and fit the slots.

const db = require('../db');
const { now, iso } = require('./today');
const { imageUrl } = require('./pieces');

// The slots in the order a look lists its pieces.
const SLOTS = ['outer layer', 'top', 'bottom', 'one-piece', 'shoes', 'bag', 'accessories'];
// How the slots are named in the member's words, in error messages.
const SLOT_WORDS = { 'outer layer': 'outer layer', top: 'top', bottom: 'bottom', 'one-piece': 'dress', shoes: 'pair of shoes', bag: 'bag' };

const MIN_PIECES = 2;
const MAX_PIECES = 12;

// One of the member's looks, or null: an id that is not theirs is the same as no look.
function findLook(userId, id) {
  const lookId = Number(id);
  if (!Number.isInteger(lookId)) return null;
  return db.prepare('SELECT * FROM looks WHERE id = ? AND user_id = ?').get(lookId, userId) ?? null;
}

const piecesOf = db.prepare(
  `SELECT pieces.*, look_pieces.slot FROM look_pieces JOIN pieces ON pieces.id = look_pieces.piece_id
   WHERE look_pieces.look_id = ? AND look_pieces.user_id = ?`
);
const occasionsOf = db.prepare(
  `SELECT look_occasions.occasion_id FROM look_occasions JOIN occasions ON occasions.id = look_occasions.occasion_id
   WHERE look_occasions.look_id = ? ORDER BY occasions.position`
);
const seasonsOf = db.prepare(
  `SELECT look_seasons.season_id FROM look_seasons JOIN seasons ON seasons.id = look_seasons.season_id
   WHERE look_seasons.look_id = ? ORDER BY seasons.position`
);

function lookJSON(look) {
  const pieces = piecesOf
    .all(look.id, look.user_id)
    .sort((a, b) => SLOTS.indexOf(a.slot) - SLOTS.indexOf(b.slot) || a.id - b.id);
  return {
    id: look.id,
    number: look.number,
    // built, photo (T9) or inspired (T10)
    source: look.source,
    // Occasion and season ids, in the member's order.
    occasions: occasionsOf.pluck().all(look.id),
    seasons: seasonsOf.pluck().all(look.id),
    pieces: pieces.map((piece) => ({
      id: piece.id,
      slot: piece.slot,
      name: piece.name,
      kind: piece.kind,
      images: {
        photo: imageUrl(piece, 'photo'),
        cutout: imageUrl(piece, 'cutout'),
        thumb: imageUrl(piece, 'thumb'),
      },
    })),
    createdAt: look.created_at,
  };
}

// Checks what the member saves on the styling table: { pieces: [piece ids], occasions: [ids],
// seasons: [ids] }. The slot of each piece follows from its kind, never from the app.
// Returns { details } or { error }.
function checkLook(body, userId) {
  const ids = (value) => (Array.isArray(value) ? [...new Set(value.map(Number))] : []);
  const pieceIds = ids(body?.pieces);
  if (pieceIds.some((id) => !Number.isInteger(id))) return { error: 'This piece is no longer in your wardrobe. Open the look again.' };
  if (pieceIds.length < MIN_PIECES) return { error: 'A look needs at least two pieces.' };
  if (pieceIds.length > MAX_PIECES) return { error: `A look holds up to ${MAX_PIECES} pieces.` };

  const findPiece = db.prepare(
    `SELECT pieces.id, kinds.slot FROM pieces JOIN kinds ON kinds.name = pieces.kind
     WHERE pieces.id = ? AND pieces.user_id = ? AND pieces.status IN ('confirmed', 'maybe')`
  );
  const pieces = pieceIds.map((id) => findPiece.get(id, userId));
  if (pieces.some((piece) => !piece)) return { error: 'This piece is no longer in your wardrobe. Open the look again.' };

  // One piece per slot, except accessories. A dress or jumpsuit takes the bottom's place.
  for (const slot of SLOTS.filter((s) => s !== 'accessories')) {
    if (pieces.filter((p) => p.slot === slot).length > 1) return { error: `One ${SLOT_WORDS[slot]} per look.` };
  }
  if (pieces.some((p) => p.slot === 'one-piece') && pieces.some((p) => p.slot === 'bottom')) {
    return { error: "A dress takes the bottom's place. Choose one of them." };
  }

  const occasions = ids(body?.occasions);
  const seasons = ids(body?.seasons);
  const ownOccasions = new Set(db.prepare('SELECT id FROM occasions WHERE user_id = ?').pluck().all(userId));
  const ownSeasons = new Set(db.prepare('SELECT id FROM seasons WHERE user_id = ?').pluck().all(userId));
  if (occasions.some((id) => !ownOccasions.has(id))) return { error: 'This occasion is no longer in your list. Open the look again.' };
  if (seasons.some((id) => !ownSeasons.has(id))) return { error: 'This season is no longer in your year. Open the look again.' };

  return { details: { pieces, occasions, seasons } };
}

// Saves a new look (lookId null) or changes one, in one go. A new look takes the number after
// the highest the member ever had, so numbers are never reused. Returns the look's id.
function saveLook(userId, lookId, details) {
  return db.transaction(() => {
    let id = lookId;
    if (id === null) {
      db.prepare('UPDATE users SET looks_numbered = looks_numbered + 1 WHERE id = ?').run(userId);
      const number = db.prepare('SELECT looks_numbered FROM users WHERE id = ?').pluck().get(userId);
      id = Number(
        db
          .prepare(`INSERT INTO looks (user_id, number, source, created_at) VALUES (?, ?, 'built', ?)`)
          .run(userId, number, iso(now())).lastInsertRowid
      );
    } else {
      for (const table of ['look_pieces', 'look_occasions', 'look_seasons']) {
        db.prepare(`DELETE FROM ${table} WHERE look_id = ? AND user_id = ?`).run(id, userId);
      }
    }

    const addPiece = db.prepare('INSERT INTO look_pieces (user_id, look_id, piece_id, slot) VALUES (?, ?, ?, ?)');
    details.pieces.forEach((piece) => addPiece.run(userId, id, piece.id, piece.slot));
    const addOccasion = db.prepare('INSERT INTO look_occasions (user_id, look_id, occasion_id) VALUES (?, ?, ?)');
    details.occasions.forEach((occasionId) => addOccasion.run(userId, id, occasionId));
    const addSeason = db.prepare('INSERT INTO look_seasons (user_id, look_id, season_id) VALUES (?, ?, ?)');
    details.seasons.forEach((seasonId) => addSeason.run(userId, id, seasonId));
    return id;
  })();
}

// After a piece is removed: a look left with no pieces goes too.
function removeEmptyLooks(userId) {
  db.prepare(
    `DELETE FROM looks WHERE user_id = ? AND NOT EXISTS (SELECT 1 FROM look_pieces WHERE look_pieces.look_id = looks.id)`
  ).run(userId);
}

module.exports = { SLOTS, findLook, lookJSON, checkLook, saveLook, removeEmptyLooks };
