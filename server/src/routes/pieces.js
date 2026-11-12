// A member's pieces: adding them, their photos, and removing them (PRD sections 5 and 8).
//
// POST   /me/pieces                   { photo, cutout }   a new piece, pictures as base64 (cutout: null when nothing lifted)
// GET    /me/pieces?status=pending    the review queue, oldest first, with the season rule per warmth
// GET    /me/pieces?chapter=tops      the counted pieces of one chapter, newest first
// PUT    /me/pieces/:id               { name, kind, colours, ..., status }   confirm (or maybe) with the member's details
// PUT    /me/pieces/:id/photo         { photo, cutout }   retake: a new photo, the same details
// GET    /me/pieces/:id/photo         the photo; also /cutout and /thumb (the thumbnail)
// DELETE /me/pieces/:id               removes the piece and its photos
//
// Every route runs behind requireMember and finds pieces by id AND the member's own id,
// so a member never reaches another member's pieces or photos. Photos are never public.

const fs = require('fs');
const express = require('express');
const db = require('../db');
const { now, iso } = require('../lib/today');
const { requireMember } = require('../middleware/signed-in');
const photos = require('../lib/photos');
const { findPiece, pieceJSON, checkDetails, saveDetails } = require('../lib/pieces');
const pieceQueue = require('../jobs/piece-queue');
const wardrobe = require('../lib/wardrobe');
const { seasonsByWarmth } = require('../lib/piece-seasons');

const router = express.Router();
router.use(requireMember);

// A new piece, from the photo (and cut-out) the app sends. It waits in the review queue
// until the member confirms it, while Claude reads its details (src/jobs/piece-queue.js).
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

    // Claude reads its details in the background; the app asks later which pieces are ready.
    pieceQueue.add(Number(id));
    res.status(201).json({ piece: pieceJSON(findPiece(req.member.id, id)) });
  } catch (error) {
    if (error instanceof photos.PhotoError) return res.status(400).json({ error: error.message });
    next(error);
  }
});

// The review queue (?status=pending), or one chapter's pieces (?chapter=).
router.get('/', (req, res) => {
  const userId = req.member.id;
  if (req.query.status === 'pending') {
    const pieces = db.prepare(`SELECT * FROM pieces WHERE user_id = ? AND status = 'pending' ORDER BY id`).all(userId);
    // So the app can propose new seasons at once when the member changes a piece's warmth.
    return res.json({ pieces: pieces.map(pieceJSON), seasonsByWarmth: seasonsByWarmth(userId) });
  }
  if (typeof req.query.chapter === 'string') {
    const pieces = db
      .prepare(
        `SELECT pieces.* FROM pieces JOIN kinds ON kinds.name = pieces.kind
         WHERE pieces.user_id = ? AND kinds.chapter = ? AND pieces.status IN ('confirmed', 'maybe')
         ORDER BY pieces.id DESC`
      )
      .all(userId, req.query.chapter);
    return res.json({ pieces: pieces.map(pieceJSON) });
  }
  res.status(400).json({ error: 'Ask for the pieces to review or for one chapter.' });
});

// Confirm a piece (or mark it maybe) with the details the member checked. Answers with the
// progress, and justUnlocked the one time this confirm opens Looks and Get the look.
router.put('/:id', (req, res) => {
  const piece = findPiece(req.member.id, req.params.id);
  if (!piece) return res.status(404).json({ error: 'This piece is no longer in your wardrobe.' });
  const checked = checkDetails(req.body, req.member.id);
  if (checked.error) return res.status(400).json({ error: checked.error });

  saveDetails(piece, checked.details, iso(now()));
  const justUnlocked = wardrobe.checkUnlock(req.member.id);
  res.json({
    piece: pieceJSON(findPiece(req.member.id, piece.id)),
    progress: wardrobe.progress(req.member.id),
    justUnlocked,
  });
});

// Retake: a new photo for a piece (offered when nothing lifted). The details stay as they
// are, so Claude is not asked again.
router.put('/:id/photo', async (req, res, next) => {
  try {
    const piece = findPiece(req.member.id, req.params.id);
    if (!piece) return res.status(404).json({ error: 'This piece is no longer in your wardrobe.' });
    const files = await photos.savePiecePhotos(req.member.id, { photo: req.body?.photo, cutout: req.body?.cutout });

    const changed = db
      .prepare('UPDATE pieces SET original_path = ?, cutout_path = ?, thumb_path = ? WHERE id = ? AND user_id = ?')
      .run(files.original, files.cutout, files.thumb, piece.id, req.member.id).changes;
    // Removed while the new photo was being saved: keep nothing.
    photos.removeFiles(changed ? photos.filesOf(piece) : files);
    if (!changed) return res.status(404).json({ error: 'This piece is no longer in your wardrobe.' });

    res.json({ piece: pieceJSON(findPiece(req.member.id, piece.id)) });
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
  res.json({ removed: piece.id, progress: wardrobe.progress(req.member.id) });
});

module.exports = router;
