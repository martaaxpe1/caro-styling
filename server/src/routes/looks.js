// A member's looks: styling them on the table, the list, one look, changing and deleting it
// (PRD sections 6 to 8, screens 12, 13 and S8).
//
// GET    /me/looks          the looks, newest first, with the member's occasions and seasons
// GET    /me/looks/table    what the styling table needs: the counted pieces with their slot,
//                           the member's occasions and seasons, and the current season
// GET    /me/looks/:id      one look for its page
// POST   /me/looks          { pieces: [ids], occasions: [ids], seasons: [ids] }   a new built look
// PUT    /me/looks/:id      the same, to change a look
// DELETE /me/looks/:id      deletes the look and its photos; its pieces stay in the edit
//
// Look from a photo (T9, screen S9):
// POST   /me/looks/spot     { photo }   which of the member's pieces Claude sees in the photo.
//                           Nothing is stored. One AI action.
// POST   /me/looks/photo    { photo, pieces, occasions, seasons }   a new look from the photo; or,
//                           if a look with the same main pieces exists, the photo is added to it
// POST   /me/looks/:id/photos             { photo }   adds a photo to one look (S8), no AI
// GET    /me/looks/:id/photos/:photo/:which   the photo, or its thumb, only to its owner
// DELETE /me/looks/:id/photos/:photo      removes one photo and its files
//
// The same look rule (PRD section 8): a look with the same outer layer, top, bottom or dress,
// and shoes as another is not saved twice. A built look answers 409 with the look it matches.
//
// Every route runs behind requireMember and requireUnlocked, and finds looks and pieces by id
// AND the member's own id. There is no route that proposes or generates a look: the member styles.
// Spotting only recognises the member's own pieces in their photo; the member confirms each one.

const fs = require('fs');
const express = require('express');
const db = require('../db');
const photos = require('../lib/photos');
const lookPhoto = require('../lib/look-photo');
const { ClaudeError } = require('../lib/claude');
const { AllowanceError } = require('../lib/allowance');
const { requireMember } = require('../middleware/signed-in');
const { requireUnlocked } = require('../middleware/unlocked');
const { pieceJSON } = require('../lib/pieces');
const { currentSeason } = require('../lib/piece-seasons');
const {
  findLook,
  lookJSON,
  checkLook,
  saveLook,
  findSameLook,
  addLookPhoto,
  insertLookPhoto,
  findLookPhoto,
  photoFiles,
  removeLookPhotoFiles,
} = require('../lib/looks');

const router = express.Router();
router.use(requireMember, requireUnlocked);

function ownSeasons(userId) {
  return db.prepare('SELECT id, name FROM seasons WHERE user_id = ? ORDER BY position').all(userId);
}

function ownOccasions(userId) {
  return db.prepare('SELECT id, name FROM occasions WHERE user_id = ? ORDER BY position').all(userId);
}

const NOT_FOUND = 'This look is no longer in your looks.';
const SPOT_FAILED = 'Caro could not find your pieces this time. Try again, or add them yourself.';

// A built look with the same main pieces as one the member has: 409, with that look.
function sameLookAnswer(res, look) {
  return res.status(409).json({ error: `You already have this look: No. ${look.number}.`, look: { id: look.id, number: look.number } });
}

// A photo the app sent that sharp could not read: 400 with the message.
function photoError(error, res, next) {
  if (error instanceof photos.PhotoError) return res.status(400).json({ error: error.message });
  return next(error);
}

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

router.post('/spot', async (req, res, next) => {
  try {
    const found = await lookPhoto.spot(req.member.id, req.body?.photo);
    res.json(found);
  } catch (error) {
    if (error instanceof AllowanceError) return res.status(429).json({ error: error.message });
    if (error instanceof ClaudeError) {
      console.error(`Look from a photo failed: ${error.message}`);
      return res.status(502).json({ error: SPOT_FAILED });
    }
    photoError(error, res, next);
  }
});

// Saves the look the member confirmed on S9, with the photo. If a look with the same main
// pieces exists, the photo is added to it and that look is not changed.
router.post('/photo', async (req, res, next) => {
  const userId = req.member.id;
  const checked = checkLook(req.body, userId);
  if (checked.error) return res.status(400).json({ error: checked.error });
  try {
    const same = findSameLook(userId, checked.details.pieces);
    if (same) {
      await addLookPhoto(userId, same.id, req.body?.photo);
      return res.json({ look: lookJSON(findLook(userId, same.id)), addedTo: true });
    }
    // The photo first, so a photo that cannot be read leaves no look without it.
    const files = await photos.saveLookPhoto(userId, req.body?.photo);
    let id;
    try {
      id = db.transaction(() => {
        const lookId = saveLook(userId, null, checked.details, 'photo');
        insertLookPhoto(userId, lookId, files);
        return lookId;
      })();
    } catch (error) {
      photos.removeFiles(files);
      throw error;
    }
    res.status(201).json({ look: lookJSON(findLook(userId, id)), addedTo: false });
  } catch (error) {
    photoError(error, res, next);
  }
});

router.post('/:id/photos', async (req, res, next) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  try {
    await addLookPhoto(req.member.id, look.id, req.body?.photo);
    res.status(201).json({ look: lookJSON(findLook(req.member.id, look.id)) });
  } catch (error) {
    photoError(error, res, next);
  }
});

// The address changes with the file (?v=), so the iPhone may keep its copy; "private" means
// only this iPhone keeps it.
router.get('/:id/photos/:photoId/:which', (req, res) => {
  const photo = findLookPhoto(req.member.id, req.params.id, req.params.photoId);
  const column = { photo: 'photo_path', thumb: 'thumb_path' }[req.params.which];
  const file = photo && column ? photos.absolute(photo[column]) : null;
  if (!file || !fs.existsSync(file)) return res.status(404).json({ error: 'Not found' });
  res.sendFile(file, { headers: { 'Cache-Control': 'private, max-age=31536000, immutable' } });
});

router.delete('/:id/photos/:photoId', (req, res) => {
  const photo = findLookPhoto(req.member.id, req.params.id, req.params.photoId);
  if (!photo) return res.status(404).json({ error: 'This photo is no longer on the look.' });
  db.prepare('DELETE FROM look_photos WHERE id = ? AND user_id = ?').run(photo.id, req.member.id);
  photos.removeFiles(photoFiles(photo));
  res.json({ look: lookJSON(findLook(req.member.id, photo.look_id)) });
});

router.get('/:id', (req, res) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  res.json({ look: lookJSON(look), occasions: ownOccasions(req.member.id), seasons: ownSeasons(req.member.id) });
});

router.post('/', (req, res) => {
  const checked = checkLook(req.body, req.member.id);
  if (checked.error) return res.status(400).json({ error: checked.error });
  const same = findSameLook(req.member.id, checked.details.pieces);
  if (same) return sameLookAnswer(res, same);
  const id = saveLook(req.member.id, null, checked.details);
  res.status(201).json({ look: lookJSON(findLook(req.member.id, id)) });
});

router.put('/:id', (req, res) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  const checked = checkLook(req.body, req.member.id);
  if (checked.error) return res.status(400).json({ error: checked.error });
  const same = findSameLook(req.member.id, checked.details.pieces, look.id);
  if (same) return sameLookAnswer(res, same);
  saveLook(req.member.id, look.id, checked.details);
  res.json({ look: lookJSON(findLook(req.member.id, look.id)) });
});

// Its pieces, occasions, seasons and photo rows go with it (ON DELETE CASCADE); the pieces
// themselves stay. Its photo files are deleted. Its number is not given again.
router.delete('/:id', (req, res) => {
  const look = findLook(req.member.id, req.params.id);
  if (!look) return res.status(404).json({ error: NOT_FOUND });
  removeLookPhotoFiles(req.member.id, [look.id]);
  db.prepare('DELETE FROM looks WHERE id = ? AND user_id = ?').run(look.id, req.member.id);
  res.json({ removed: look.id });
});

module.exports = router;
