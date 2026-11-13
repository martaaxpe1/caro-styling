// Find it and To find (PRD sections 7 and 8, screen S11, T11).
//
// GET  /me/to-find/:id                       the Find it page: the piece, its inspiration, the
//                                            search state, the products found, stores not searched
// POST /me/to-find/:id/search                Find it or Search again (one AI action, in the background)
// PUT  /me/to-find/:id/results/:rid          { decision: 'kept' | 'discarded' | null }: swipe right or left
// GET  /me/to-find/:id/results/:rid/image    the product's picture, fetched from the store by the server
// POST /me/to-find/:id/bought                { result, photo, cutout }: adds the piece to the edit with
//                                            the store's picture, cropped on the phone. No AI action.
// PUT  /me/to-find/:id                       { status: 'dropped' }: no longer looking for it
//
// Every route runs behind requireMember and requireUnlocked and finds rows by id AND the
// member's own id. A search runs only on the member's tap, for one piece, in their stores.

const express = require('express');
const sharp = require('sharp');
const db = require('../db');
const photos = require('../lib/photos');
const search = require('../lib/store-search');
const pieceSeasons = require('../lib/piece-seasons');
const queue = require('../jobs/search-queue');
const { findPiece, pieceJSON } = require('../lib/pieces');
const { requireMember } = require('../middleware/signed-in');
const { requireUnlocked } = require('../middleware/unlocked');
const { now, iso } = require('../lib/today');

const router = express.Router();
router.use(requireMember, requireUnlocked);

const NOT_FOUND = 'This piece is no longer on To find.';
const IMAGE_BYTES = 8 * 1024 * 1024;

function pageJSON(userId, toFind) {
  const row = db.prepare('SELECT * FROM inspiration_pieces WHERE id = ? AND user_id = ?').get(toFind.inspiration_piece_id, userId);
  const found = db.prepare('SELECT * FROM inspirations WHERE id = ? AND user_id = ?').get(row.inspiration_id, userId);
  const member = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  const { searched, skipped } = search.storesFor(member);
  const boughtPiece = toFind.piece_id ? findPiece(userId, toFind.piece_id) : null;
  return {
    id: toFind.id,
    status: toFind.status,
    inspiration: { id: found.id, thumb: `/me/inspirations/${found.id}/photo/thumb?v=${found.thumb_path.split('/').pop().split('-')[0]}` },
    number: row.number,
    description: row.description,
    kind: row.kind,
    searchStatus: toFind.search_status,
    searchMessage: toFind.search_message,
    searchedAt: toFind.searched_at,
    results: search.resultsOf(userId, toFind.id),
    // For prices and dates in the member's own format.
    country: member.country,
    stores: searched.map((s) => s.name),
    notSearched: skipped.map((s) => s.reason),
    piece: boughtPiece ? pieceJSON(boughtPiece) : null,
  };
}

function find(req, res) {
  const toFind = search.findToFind(req.member.id, req.params.id);
  if (!toFind) res.status(404).json({ error: NOT_FOUND });
  return toFind;
}

function findResult(userId, toFindId, id) {
  const resultId = Number(id);
  if (!Number.isInteger(resultId)) return null;
  return db.prepare('SELECT * FROM store_results WHERE id = ? AND to_find_id = ? AND user_id = ?').get(resultId, toFindId, userId) ?? null;
}

router.get('/:id', (req, res) => {
  const toFind = find(req, res);
  if (!toFind) return;
  res.json({ toFind: pageJSON(req.member.id, toFind) });
});

router.post('/:id/search', (req, res) => {
  const toFind = find(req, res);
  if (!toFind) return;
  if (toFind.search_status !== 'searching') {
    const refused = search.startSearch(req.member.id, toFind);
    if (refused) return res.status(refused.status ?? 400).json({ error: refused.error });
    queue.add(toFind.id);
  }
  res.json({ toFind: pageJSON(req.member.id, search.findToFind(req.member.id, toFind.id)) });
});

router.put('/:id', (req, res) => {
  const toFind = find(req, res);
  if (!toFind) return;
  if (req.body?.status !== 'dropped') return res.status(400).json({ error: 'Only dropping a piece is possible here.' });
  db.prepare(`UPDATE to_find SET status = 'dropped' WHERE id = ? AND user_id = ?`).run(toFind.id, req.member.id);
  res.json({ dropped: toFind.id });
});

router.put('/:id/results/:rid', (req, res) => {
  const toFind = find(req, res);
  if (!toFind) return;
  const result = findResult(req.member.id, toFind.id, req.params.rid);
  if (!result) return res.status(404).json({ error: 'This product is no longer in the results.' });
  const decision = req.body?.decision ?? null;
  if (![null, 'kept', 'discarded'].includes(decision)) return res.status(400).json({ error: 'Keep or discard it.' });
  db.prepare('UPDATE store_results SET decision = ? WHERE id = ? AND user_id = ?').run(decision, result.id, req.member.id);
  res.json({ toFind: pageJSON(req.member.id, toFind) });
});

// The product's picture. The server fetches it from the address the search found, so the
// app shows it like any other picture. Images only, at most 8 MB, 10 seconds.
router.get('/:id/results/:rid/image', async (req, res, next) => {
  const toFind = find(req, res);
  if (!toFind) return;
  const result = findResult(req.member.id, toFind.id, req.params.rid);
  if (!result?.image_url) return res.status(404).json({ error: 'This product has no picture.' });
  try {
    const response = await fetch(result.image_url, { signal: AbortSignal.timeout(10000), redirect: 'follow' });
    const type = response.headers.get('content-type') ?? '';
    if (!response.ok || !type.startsWith('image/')) return res.status(404).json({ error: 'The store did not send the picture.' });
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > IMAGE_BYTES) return res.status(404).json({ error: 'The picture is too large.' });
    // As JPEG, whatever the store sends (WebP, AVIF), so the iPhone can always read it.
    const jpeg = await sharp(bytes).rotate().resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer();
    res.set('Cache-Control', 'private, max-age=86400').type('image/jpeg').send(jpeg);
  } catch (error) {
    if (error.name === 'TimeoutError' || error.name === 'TypeError' || /unsupported image|Input buffer/i.test(error.message)) {
      return res.status(404).json({ error: 'The store did not send the picture.' });
    }
    next(error);
  }
});

// Bought: the piece goes into the edit with the store's picture, which the member cropped on
// the phone, confirmed and ready. Its details come from the inspiration (kind, main colour),
// the store (brand) and the product (price paid). It fills the piece in the member's version.
// When the real piece arrives, Retake on its page swaps in the member's own photo.
router.post('/:id/bought', async (req, res, next) => {
  const userId = req.member.id;
  const toFind = find(req, res);
  if (!toFind) return;
  if (toFind.status === 'bought') return res.status(409).json({ error: 'You already bought this piece.' });
  const result = findResult(userId, toFind.id, req.body?.result);
  if (!result) return res.status(404).json({ error: 'This product is no longer in the results.' });
  const row = db.prepare('SELECT * FROM inspiration_pieces WHERE id = ? AND user_id = ?').get(toFind.inspiration_piece_id, userId);
  const store = db.prepare('SELECT name FROM stores WHERE id = ? AND user_id = ?').get(result.store_id, userId);

  let files;
  try {
    files = await photos.savePiecePhotos(userId, { photo: req.body?.photo, cutout: req.body?.cutout });
  } catch (error) {
    if (error instanceof photos.PhotoError) return res.status(400).json({ error: error.message });
    return next(error);
  }

  try {
    const pieceId = db.transaction(() => {
      const at = iso(now());
      // Without a kind from the inspiration, the piece waits in the review queue for one.
      const status = row.kind ? 'confirmed' : 'pending';
      const id = Number(
        db
          .prepare(
            `INSERT INTO pieces (user_id, status, details_status, name, kind, warmth, brand, price_cents, price_currency,
               store_photo, original_path, cutout_path, thumb_path, created_at, confirmed_at)
             VALUES (?, ?, 'suggested', ?, ?, 'medium', ?, ?, ?, ?, ?, ?, ?, ?, ?)`
          )
          .run(
            userId, status, row.description.slice(0, 60), row.kind, store?.name ?? null, result.price_cents, result.currency,
            store?.name ?? 'the store', files.original, files.cutout, files.thumb, at, status === 'confirmed' ? at : null
          ).lastInsertRowid
      );
      if (row.colour) db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, 1)').run(userId, id, row.colour);
      // Medium warmth: every season in most years. The member can change it on the piece's page.
      pieceSeasons.proposeForPiece(userId, id, 'medium');
      db.prepare('UPDATE inspiration_pieces SET filled_piece_id = ? WHERE id = ?').run(id, row.id);
      db.prepare(`UPDATE to_find SET status = 'bought', piece_id = ? WHERE id = ?`).run(id, toFind.id);
      db.prepare(`UPDATE store_results SET decision = 'kept' WHERE id = ?`).run(result.id);
      return id;
    })();
    res.status(201).json({ piece: pieceJSON(findPiece(userId, pieceId)), inspiration: row.inspiration_id });
  } catch (error) {
    photos.removeFiles(files);
    next(error);
  }
});

module.exports = router;
