// The wardrobe as a whole. Signed in, the member's own pieces only.
//
// GET  /me/wardrobe                    what the edit shows (screens 08 and 10): progress, pieces still
//                                      waiting, the current season, and each chapter with its counts
// GET  /me/wardrobe/overview           the wardrobe overview (S7): facts by chapter, colour, season, occasion
// GET  /me/wardrobe/seasons-to-check   after the member changed the number of seasons: the pieces
//                                      to check, grouped by warmth, with the seasons proposed for each
// POST /me/wardrobe/seasons-to-check   { light: [season ids], medium, warm, none }: confirm them in one batch

const express = require('express');
const db = require('../db');
const { requireMember } = require('../middleware/signed-in');
const { wardrobeJSON } = require('../lib/wardrobe');
const { overviewJSON } = require('../lib/overview');
const { imageUrl } = require('../lib/pieces');
const pieceSeasons = require('../lib/piece-seasons');

const router = express.Router();
router.use(requireMember);

router.get('/', (req, res) => {
  res.json(wardrobeJSON(req.member.id));
});

router.get('/overview', (req, res) => {
  res.json(overviewJSON(req.member.id));
});

function seasonsOf(userId) {
  return db.prepare('SELECT id, name FROM seasons WHERE user_id = ? ORDER BY position').all(userId);
}

router.get('/seasons-to-check', (req, res) => {
  const userId = req.member.id;
  const rule = pieceSeasons.seasonsByWarmth(userId);
  const pieces = pieceSeasons.piecesToCheck(userId);
  const groups = pieceSeasons.GROUPS.map((warmth) => ({
    warmth,
    seasons: warmth === 'none' ? [] : rule[warmth],
    pieces: pieces
      .filter((p) => (p.warmth ?? 'none') === warmth)
      .map((p) => ({ id: p.id, name: p.name, thumb: imageUrl(p, 'thumb'), hasCutout: Boolean(p.cutout_path) })),
  })).filter((group) => group.pieces.length > 0);
  res.json({ seasons: seasonsOf(userId), groups });
});

router.post('/seasons-to-check', (req, res) => {
  const userId = req.member.id;
  const own = new Set(seasonsOf(userId).map((s) => s.id));
  const groups = {};
  for (const warmth of pieceSeasons.GROUPS) {
    const value = req.body?.[warmth];
    if (value === undefined) continue;
    if (!Array.isArray(value)) return res.status(400).json({ error: 'Choose the seasons for each group.' });
    const ids = [...new Set(value.map(Number))];
    if (ids.some((id) => !own.has(id))) {
      return res.status(400).json({ error: 'This season is no longer in your year. Open the check again.' });
    }
    groups[warmth] = ids;
  }
  const confirmed = pieceSeasons.confirmBatch(userId, groups);
  res.json({ confirmed, wardrobe: wardrobeJSON(userId) });
});

module.exports = router;
