// A member's pieces: adding them, their photos, and removing them (PRD sections 5 and 8).
//
// POST   /me/pieces              { photo, cutout }   a new piece, pictures as base64 (cutout: null when nothing lifted)
// GET    /me/pieces/:id/photo    the photo; also /cutout and /thumb (the thumbnail)
// DELETE /me/pieces/:id          removes the piece and its photos
//
// Every route runs behind requireMember and finds pieces by id AND the member's own id,
// so a member never reaches another member's pieces or photos. Photos are never public.

const fs = require('fs');
const express = require('express');
const db = require('../db');
const { now, iso } = require('../lib/today');
const { requireMember } = require('../middleware/signed-in');
const photos = require('../lib/photos');
const { findPiece, pieceJSON } = require('../lib/pieces');

const router = express.Router();
router.use(requireMember);

// A new piece, from the photo (and cut-out) the app sends. It waits in the review queue
// until the member confirms it.
router.post('/', async (req, res, next) => {
  try {
    const files = await photos.savePiecePhotos(req.member.id, {
      photo: req.body?.photo,
      cutout: req.body?.cutout,
    });
    const { lastInsertRowid: id } = db
      .prepare(
        `INSERT INTO pieces (user_id, status, original_path, cutout_path, thumb_path, created_at)
         VALUES (?, 'pending', ?, ?, ?, ?)`
      )
      .run(req.member.id, files.original, files.cutout, files.thumb, iso(now()));

    res.status(201).json({ piece: pieceJSON(findPiece(req.member.id, id)) });
  } catch (error) {
    if (error instanceof photos.PhotoError) return res.status(400).json({ error: error.message });
    next(error);
  }
});

// One of a piece's pictures. The address changes when the photo does (?v=), so the iPhone
// may keep its copy for good. "private" means only this iPhone keeps it, never a shared cache.
const PICTURES = { photo: 'original_path', cutout: 'cutout_path', thumb: 'thumb_path' };

router.get('/:id/:which', (req, res) => {
  const column = PICTURES[req.params.which];
  const piece = column ? findPiece(req.member.id, req.params.id) : null;
  const file = piece?.[column] ? photos.absolute(piece[column]) : null;
  if (!file || !fs.existsSync(file)) return res.status(404).json({ error: 'Not found' });

  res.sendFile(file, { headers: { 'Cache-Control': 'private, max-age=31536000, immutable' } });
});

// Removes a piece and its photos. If Looks and Get the look are open, they stay open.
router.delete('/:id', (req, res) => {
  const piece = findPiece(req.member.id, req.params.id);
  if (!piece) return res.status(404).json({ error: 'This piece is no longer in your wardrobe.' });

  // Its colours, seasons, occasions and places in looks go with it (ON DELETE CASCADE).
  db.prepare('DELETE FROM pieces WHERE id = ? AND user_id = ?').run(piece.id, req.member.id);
  photos.removeFiles(photos.filesOf(piece));
  res.json({ removed: piece.id });
});

module.exports = router;
