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
const { currentSeason } = require('./piece-seasons');

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

// How many looks the member has saved. Until the first one, "not styled yet" waits (PRD section 7).
function looksCount(userId) {
  return db.prepare('SELECT COUNT(*) FROM looks WHERE user_id = ?').pluck().get(userId);
}

// What the edit shows (screens 08 and 10): progress, pieces still being read or waiting for
// review, the current season for the dateline, how many pieces have new seasons to check, and
// each chapter with pieces: its count, how many are in no look (once there is a look), and its
// three newest cut-outs. Pieces that don't fit yet (T13) are counted, but they are not "not styled
// yet", and their cut-outs show only in a chapter with no others.
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
      `SELECT chapters.name, chapters.number, COUNT(pieces.id) AS count,
         COALESCE(SUM(pieces.fits = 1 AND NOT EXISTS (SELECT 1 FROM look_pieces WHERE look_pieces.piece_id = pieces.id)), 0) AS not_styled,
         MAX(pieces.fits) AS any_fits
       FROM chapters
       JOIN kinds ON kinds.chapter = chapters.name
       JOIN pieces ON pieces.kind = kinds.name AND pieces.user_id = ? AND ${COUNTED}
       GROUP BY chapters.name ORDER BY chapters.number`
    )
    .all(userId);

  const newest = db.prepare(
    `SELECT pieces.* FROM pieces JOIN kinds ON kinds.name = pieces.kind
     WHERE pieces.user_id = ? AND kinds.chapter = ? AND pieces.fits = ? AND ${COUNTED}
     ORDER BY pieces.id DESC LIMIT 3`
  );

  const looks = looksCount(userId);
  const seasonsToCheck = db
    .prepare(`SELECT COUNT(*) FROM pieces WHERE user_id = ? AND seasons_to_check = 1 AND ${COUNTED}`)
    .pluck()
    .get(userId);

  return {
    progress: progress(userId),
    waiting: { reading: waiting.reading, toReview: waiting.to_review },
    currentSeason: currentSeason(userId),
    looks,
    seasonsToCheck,
    chapters: chapters.map((chapter) => ({
      name: chapter.name,
      number: chapter.number,
      count: chapter.count,
      notStyled: looks > 0 ? chapter.not_styled : null,
      thumbs: newest.all(userId, chapter.name, chapter.any_fits).map((piece) => imageUrl(piece, 'thumb')),
    })),
  };
}

// For the app's start: has the member added any piece yet? Step 6 shows until they have.
function hasPieces(userId) {
  return Boolean(db.prepare('SELECT 1 FROM pieces WHERE user_id = ? LIMIT 1').get(userId));
}

module.exports = { NEEDED, COUNTED, progress, checkUnlock, looksCount, wardrobeJSON, hasPieces };
