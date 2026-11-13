// Get the look (PRD sections 6 to 8, screens 14 and 15, T10): inspirations, your version of
// each, and the To find list.
//
// GET    /me/inspirations                 the home: inspirations newest first with "N of M yours",
//                                         the To find list, the member's occasions
// POST   /me/inspirations                 { photo } or { link } (a Pinterest link), and { link, note }
//                                         saves it and starts reading it in the background (one AI action)
// GET    /me/inspirations/:id             one inspiration: the photo, the pieces found, your version
// PUT    /me/inspirations/:id             { link, note, occasion }
// DELETE /me/inspirations/:id             deletes it, its photo files and its To find pieces; a look
//                                         saved from it stays, unless it holds none of the member's pieces
// POST   /me/inspirations/:id/read        Try again, after Claude could not read it
// PUT    /me/inspirations/:id/pieces/:n   { piece, removed, key }: your piece for it, take it out,
//                                         mark a missing piece as key (it goes on To find)
// POST   /me/inspirations/:id/look        { occasions, seasons }: saves your version as a look
// GET    /me/inspirations/:id/photo/:which   the photo or its thumb, only to its owner
//
// Every route runs behind requireMember and requireUnlocked and finds rows by id AND the
// member's own id. Claude describes and compares; the member makes the version. Nothing here
// proposes a look or suggests buying.

const fs = require('fs');
const express = require('express');
const db = require('../db');
const photos = require('../lib/photos');
const inspiration = require('../lib/inspiration');
const sharedLink = require('../lib/shared-link');
const queue = require('../jobs/inspiration-queue');
const allowance = require('../lib/allowance');
const storeSearch = require('../lib/store-search');
const searchQueue = require('../jobs/search-queue');
const { requireMember } = require('../middleware/signed-in');
const { requireUnlocked } = require('../middleware/unlocked');
const { checkLook, saveLook, findSameLook, findLook, lookJSON, removeEmptyLooks } = require('../lib/looks');
const { now, iso } = require('../lib/today');

const router = express.Router();
router.use(requireMember, requireUnlocked);

const NOT_FOUND = 'This inspiration is no longer in Get the look.';
const NOTE_LENGTH = 300;
const LINK_LENGTH = 2000;

function ownOccasions(userId) {
  return db.prepare('SELECT id, name FROM occasions WHERE user_id = ? ORDER BY position').all(userId);
}

// A link the member gave or shared: kept only when it is a web address.
function cleanLink(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value.trim());
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    return url.href.slice(0, LINK_LENGTH);
  } catch {
    return null;
  }
}

function cleanNote(value) {
  if (typeof value !== 'string') return null;
  return value.trim().slice(0, NOTE_LENGTH) || null;
}

function startSearchFor(userId, inspirationId, number) {
  const toFind = db
    .prepare(
      `SELECT to_find.* FROM to_find JOIN inspiration_pieces ON inspiration_pieces.id = to_find.inspiration_piece_id
       WHERE inspiration_pieces.inspiration_id = ? AND inspiration_pieces.number = ? AND to_find.user_id = ? AND to_find.status = 'considering'`
    )
    .get(inspirationId, number, userId);
  if (!toFind || toFind.search_status === 'searching' || toFind.searched_at) return;
  const refused = storeSearch.startSearch(userId, toFind);
  if (refused) {
    db.prepare(`UPDATE to_find SET search_status = 'failed', search_message = ? WHERE id = ?`).run(refused.error, toFind.id);
    return;
  }
  searchQueue.add(toFind.id);
}

function sendInspiration(res, userId, id, status = 200) {
  res.status(status).json({ inspiration: inspiration.inspirationJSON(inspiration.findInspiration(userId, id)) });
}

router.get('/', (req, res) => {
  const userId = req.member.id;
  const rows = db.prepare('SELECT * FROM inspirations WHERE user_id = ? ORDER BY created_at DESC, id DESC').all(userId);
  res.json({
    inspirations: rows.map(inspiration.summaryJSON),
    toFind: inspiration.toFindJSON(userId),
    occasions: ownOccasions(userId),
  });
});

router.post('/', async (req, res, next) => {
  const userId = req.member.id;
  let image = req.body?.photo;
  let link = cleanLink(req.body?.link);
  if (!allowance.hasRoom(userId)) return res.status(429).json({ error: allowance.message() });
  try {
    if (!image) {
      if (!link) return res.status(400).json({ error: 'The image did not arrive. Try again.' });
      if (!sharedLink.isPinterestLink(link)) return res.status(400).json({ error: sharedLink.NOT_PINTEREST });
      const found = await sharedLink.remote.imageFromLink(link);
      image = found.image;
      link = found.link;
    }
    const files = await photos.saveInspirationPhoto(userId, image);
    const id = Number(
      db
        .prepare(
          `INSERT INTO inspirations (user_id, photo_path, thumb_path, link, note, status, created_at) VALUES (?, ?, ?, ?, ?, 'reading', ?)`
        )
        .run(userId, files.photo, files.thumb, link, cleanNote(req.body?.note), iso(now())).lastInsertRowid
    );
    queue.add(id);
    sendInspiration(res, userId, id, 201);
  } catch (error) {
    if (error instanceof sharedLink.LinkError || error instanceof photos.PhotoError) {
      return res.status(400).json({ error: error.message });
    }
    next(error);
  }
});

router.get('/:id', (req, res) => {
  const found = inspiration.findInspiration(req.member.id, req.params.id);
  if (!found) return res.status(404).json({ error: NOT_FOUND });
  sendInspiration(res, req.member.id, found.id);
});

router.put('/:id', (req, res) => {
  const userId = req.member.id;
  const found = inspiration.findInspiration(userId, req.params.id);
  if (!found) return res.status(404).json({ error: NOT_FOUND });
  const body = req.body ?? {};
  if ('occasion' in body && body.occasion !== null) {
    const own = db.prepare('SELECT 1 FROM occasions WHERE id = ? AND user_id = ?').get(Number(body.occasion), userId);
    if (!own) return res.status(400).json({ error: 'This occasion is no longer in your list.' });
  }
  if ('link' in body && body.link && !cleanLink(body.link)) {
    return res.status(400).json({ error: 'This link is not a web address.' });
  }
  db.prepare('UPDATE inspirations SET link = ?, note = ?, occasion_id = ? WHERE id = ? AND user_id = ?').run(
    'link' in body ? cleanLink(body.link) : found.link,
    'note' in body ? cleanNote(body.note) : found.note,
    'occasion' in body ? (body.occasion === null ? null : Number(body.occasion)) : found.occasion_id,
    found.id,
    userId
  );
  sendInspiration(res, userId, found.id);
});

router.delete('/:id', (req, res) => {
  const found = inspiration.findInspiration(req.member.id, req.params.id);
  if (!found) return res.status(404).json({ error: NOT_FOUND });
  db.prepare('DELETE FROM inspirations WHERE id = ? AND user_id = ?').run(found.id, req.member.id);
  inspiration.removePhotoFiles(found);
  // A look in progress saved from it with none of the member's pieces has nothing left.
  removeEmptyLooks(req.member.id);
  res.json({ removed: found.id });
});

router.post('/:id/read', (req, res) => {
  const found = inspiration.findInspiration(req.member.id, req.params.id);
  if (!found) return res.status(404).json({ error: NOT_FOUND });
  if (found.status === 'not read') {
    if (!allowance.hasRoom(req.member.id)) return res.status(429).json({ error: allowance.message() });
    db.prepare(`UPDATE inspirations SET status = 'reading' WHERE id = ?`).run(found.id);
    queue.add(found.id);
  }
  sendInspiration(res, req.member.id, found.id);
});

router.put('/:id/pieces/:number', (req, res) => {
  const found = inspiration.findInspiration(req.member.id, req.params.id);
  if (!found) return res.status(404).json({ error: NOT_FOUND });
  const refused = inspiration.changePiece(req.member.id, found, req.params.number, req.body ?? {});
  if (refused) return res.status(refused.status).json({ error: refused.error });
  // Marking a piece as key is the member's tap for this one piece: Caro searches their stores
  // for it at once (Marta's choice in T10). If it cannot search, the piece is still key, and
  // the reason shows on To find.
  if (req.body?.key === true) startSearchFor(req.member.id, found.id, Number(req.params.number));
  sendInspiration(res, req.member.id, found.id);
});

// Saves the member's version as a look: their own piece for each piece they kept. Saving again
// changes that same look. The same look rule (PRD section 8) holds, as on the styling table.
// It can be saved before every piece is found: while pieces are missing, the look is in progress.
router.post('/:id/look', (req, res) => {
  const userId = req.member.id;
  const found = inspiration.findInspiration(userId, req.params.id);
  if (!found) return res.status(404).json({ error: NOT_FOUND });
  const checked = checkLook(
    { pieces: inspiration.versionPieceIds(userId, found), occasions: req.body?.occasions, seasons: req.body?.seasons },
    userId,
    { minPieces: 0 }
  );
  if (checked.error) return res.status(400).json({ error: checked.error });

  const existing = found.look_id ? findLook(userId, found.look_id) : null;
  const same = findSameLook(userId, checked.details.pieces, existing?.id ?? null);
  if (same) {
    return res.status(409).json({ error: `You already have this look: No. ${same.number}.`, look: { id: same.id, number: same.number } });
  }
  const lookId = db.transaction(() => {
    const id = saveLook(userId, existing ? existing.id : null, checked.details, 'inspired');
    db.prepare('UPDATE inspirations SET look_id = ? WHERE id = ?').run(id, found.id);
    return id;
  })();
  res.status(existing ? 200 : 201).json({ look: lookJSON(findLook(userId, lookId)) });
});

// The address changes with the file (?v=), so the iPhone may keep its copy.
router.get('/:id/photo/:which', (req, res) => {
  const found = inspiration.findInspiration(req.member.id, req.params.id);
  const column = { photo: 'photo_path', thumb: 'thumb_path' }[req.params.which];
  const file = found && column ? photos.absolute(found[column]) : null;
  if (!file || !fs.existsSync(file)) return res.status(404).json({ error: 'Not found' });
  res.sendFile(file, { headers: { 'Cache-Control': 'private, max-age=31536000, immutable' } });
});

module.exports = router;
