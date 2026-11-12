// A member's looks: styling them on the table, the list, one look, changing and deleting it
// (PRD sections 6 to 8, screens 12, 13 and S8).
//
// GET    /me/looks          the looks, newest first, with the member's occasions and seasons
// GET    /me/looks/table    what the styling table needs: the counted pieces with their slot,
//                           the member's occasions and seasons, and the current season
// GET    /me/looks/:id      one look for its page
// POST   /me/looks          { pieces: [ids], occasions: [ids], seasons: [ids] }   a new built look
// PUT    /me/looks/:id      the same, to change a look
// DELETE /me/looks/:id      deletes the look; its pieces stay in the edit
//
// Every route runs behind requireMember and requireUnlocked, and finds looks and pieces by id
// AND the member's own id. There is no route that proposes or generates a look: the member styles.

const express = require('express');
const db = require('../db');
const { requireMember } = require('../middleware/signed-in');
const { requireUnlocked } = require('../middleware/unlocked');
const { pieceJSON } = require('../lib/pieces');
const { currentSeason } = require('../lib/piece-seasons');
const { findLook, lookJSON, checkLook, saveLook } = require('../lib/looks');

const router = express.Router();
router.use(requireMember, requireUnlocked);

function ownSeasons(userId) {
  return db.prepare('SELECT id, name FROM seasons WHERE user_id = ? ORDER BY position').all(userId);
}

function ownOccasions(userId) {
  return db.prepare('SELECT id, name FROM occasions WHERE user_id = ? ORDER BY position').all(userId);
}

const NOT_FOUND = 'This look is no longer in your looks.';

router.get('/', (req, res) => {
  const userId = req.member.id;
  const looks = db.prepare('SELECT * FROM looks WHERE user_id = ? ORDER BY number DESC').all(userId);
  res.json({ looks: looks.map(lookJSON), occasions: ownOccasions(userId), seasons: ownSeasons(userId) });
});

// The pieces the tray chooses from: everything counted in the edit, newest first. The phone
// puts the current season first; it never hides a piece.
router.get('/table', (req, res) => {
  const userId = req.member.id;
  const pieces = db
    .prepare(
      `SELECT pieces.* FROM pieces JOIN kinds ON kinds.name = pieces.kind
       WHERE pieces.user_id = ? AND pieces.status IN ('confirmed', 'maybe') ORDER BY pieces.id DESC`
    )
    .all(userId);
  res.json({
    pieces: pieces.map(pieceJSON),
    occasions: ownOccasions(userId),
    seasons: ownSeasons(userId),
    currentSeason: currentSeason(userId),
  });
});

router.get('/:id', (req, res) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  res.json({ look: lookJSON(look), occasions: ownOccasions(req.member.id), seasons: ownSeasons(req.member.id) });
});

router.post('/', (req, res) => {
  const checked = checkLook(req.body, req.member.id);
  if (checked.error) return res.status(400).json({ error: checked.error });
  const id = saveLook(req.member.id, null, checked.details);
  res.status(201).json({ look: lookJSON(findLook(req.member.id, id)) });
});

router.put('/:id', (req, res) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  const checked = checkLook(req.body, req.member.id);
  if (checked.error) return res.status(400).json({ error: checked.error });
  saveLook(req.member.id, look.id, checked.details);
  res.json({ look: lookJSON(findLook(req.member.id, look.id)) });
});

// Its pieces, occasions and seasons go with it (ON DELETE CASCADE); the pieces themselves stay.
// Its number is not given again. Photos of the member wearing it come in T9: delete their
// files here then.
router.delete('/:id', (req, res) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  db.prepare('DELETE FROM looks WHERE id = ? AND user_id = ?').run(look.id, req.member.id);
  res.json({ removed: look.id });
});

module.exports = router;
