// The wardrobe as a whole: progress towards the unlock, and the unlock rule (PRD sections 5 and 8).
//
// The unlock rule is checked here, on the server, never in the app:
// Looks and Get the look open at 20 counted pieces with at least one top, one bottom or
// one-piece, and one pair of shoes. Counted pieces are confirmed or maybe; pieces still
// waiting in the review queue do not count. Once open, they stay open: unlocked_at is set
// once and never cleared, even if pieces are removed later.

const db = require('../db');
const { now, iso } = require('./today');
const { imageUrl } = require('./pieces');

const NEEDED = 20;

const COUNTED = `pieces.status IN ('confirmed', 'maybe')`;

function progress(userId) {
  const counts = db
    .prepare(
      `SELECT COUNT(*) AS pieces,
         COALESCE(SUM(kinds.slot = 'top'), 0) AS tops,
         COALESCE(SUM(kinds.slot IN ('bottom', 'one-piece')), 0) AS bottoms,
         COALESCE(SUM(kinds.slot = 'shoes'), 0) AS shoes
       FROM pieces JOIN kinds ON kinds.name = pieces.kind
       WHERE pieces.user_id = ? AND ${COUNTED}`
    )
    .get(userId);
  const unlockedAt = db.prepare('SELECT unlocked_at FROM users WHERE id = ?').pluck().get(userId);

  return {
    pieces: counts.pieces,
    needed: NEEDED,
    top: counts.tops > 0,
    bottomOrOnePiece: counts.bottoms > 0,
    shoes: counts.shoes > 0,
    unlocked: Boolean(unlockedAt),
  };
}

function ruleMet(p) {
  return p.pieces >= NEEDED && p.top && p.bottomOrOnePiece && p.shoes;
}

// Called after every confirm. Returns true only the moment Looks and Get the look open,
// so the app shows "Your wardrobe is open" once.
function checkUnlock(userId) {
  const p = progress(userId);
  if (p.unlocked || !ruleMet(p)) return false;
  const opened = db.prepare('UPDATE users SET unlocked_at = ? WHERE id = ? AND unlocked_at IS NULL').run(iso(now()), userId);
  return opened.changes === 1;
}

// What the edit shows (screen 08): progress, pieces still being read or waiting for review,
// and each chapter with pieces, with its count and its two newest cut-outs.
function wardrobeJSON(userId) {
  const waiting = db
    .prepare(
      `SELECT COALESCE(SUM(details_status = 'reading'), 0) AS reading,
         COALESCE(SUM(details_status <> 'reading'), 0) AS to_review
       FROM pieces WHERE user_id = ? AND status = 'pending'`
    )
    .get(userId);

  const chapters = db
    .prepare(
      `SELECT chapters.name, chapters.number, COUNT(pieces.id) AS count
       FROM chapters
       JOIN kinds ON kinds.chapter = chapters.name
       JOIN pieces ON pieces.kind = kinds.name AND pieces.user_id = ? AND ${COUNTED}
       GROUP BY chapters.name ORDER BY chapters.number`
    )
    .all(userId);

  const newest = db.prepare(
    `SELECT pieces.* FROM pieces JOIN kinds ON kinds.name = pieces.kind
     WHERE pieces.user_id = ? AND kinds.chapter = ? AND ${COUNTED}
     ORDER BY pieces.id DESC LIMIT 2`
  );

  return {
    progress: progress(userId),
    waiting: { reading: waiting.reading, toReview: waiting.to_review },
    chapters: chapters.map((chapter) => ({
      name: chapter.name,
      number: chapter.number,
      count: chapter.count,
      thumbs: newest.all(userId, chapter.name).map((piece) => imageUrl(piece, 'thumb')),
    })),
  };
}

// For the app's start: has the member added any piece yet? Step 6 shows until they have.
function hasPieces(userId) {
  return Boolean(db.prepare('SELECT 1 FROM pieces WHERE user_id = ? LIMIT 1').get(userId));
}

module.exports = { NEEDED, progress, checkUnlock, wardrobeJSON, hasPieces };
