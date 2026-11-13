// Get the look (PRD sections 6 to 8 and 10, screens 14 and 15): an inspiration is a photo of
// a look the member likes. Claude describes each piece in it and finds the member's closest
// piece of the same kind, marked yours, close or missing. The member then makes their version.
//
// The prompt is the one the T1 spike tested (server/spike/3-inspirations.js, docs/SPIKE.md
// test 3), with "close" as Marta chose it: the same kind and a similar colour. Claude gets the
// member's wardrobe the same way as for a look from a photo (src/lib/look-photo.js): each
// counted piece as a small picture and one line, numbered, and the answer form only allows
// those numbers. So Claude can only name the member's own pieces.
//
// Claude only describes and compares. It never says what goes with what, never completes a
// look and never suggests buying: the member decides which missing piece is key.
//
// Every function takes the member's own id and touches only their rows.

const path = require('path');
const db = require('../db');
const photos = require('./photos');
const lists = require('./lists');
const { ask, recordAiAction } = require('./claude');
const allowance = require('./allowance');
const { pieceJSON } = require('./pieces');
const { now, iso } = require('./today');
const lookPhoto = require('./look-photo');

const PHOTO_SIZE = 1568;
const MAX_PIECES = 8;
const MATCHES = ['yours', 'close', 'missing'];

function instructions() {
  return `The image above is an inspiration: a look I like. Describe each piece in it, then find the closest piece I own of the same kind.

For each piece of clothing, shoes, bag or accessory you can see in the inspiration, at most ${MAX_PIECES}, the most visible first:
- description: a short name of 2 to 5 words in sentence case, like "Grey oversized blazer"
- kind and chapter, from this list:
${lists.kindsByChapterText()}
- colours (main colour first), pattern and material, from the lists. Material "not sure" when you cannot tell.
- shape: a few words on the cut or fit, like "oversized, single-breasted"
- x and y: where the piece is in the image, as the point at its centre. x in percent of the image width from the left edge, y in percent of the image height from the top edge, each 0 to 100.
- closest_piece: the number of my piece of the same kind (or a near kind in the same chapter, like a jacket for a blazer) that is most like it, or "none" if I have nothing of that kind
- match:
  - yours: my piece is very much like it, with the same kind, colour and shape
  - close: my piece is the same or a near kind and a similar colour (the same colour or a close shade, like cream and white, or camel and beige), but differs in shape or material
  - missing: anything else. A piece of the same kind in another colour is missing, not close. closest_piece still names my nearest piece of that kind, if I have one.

Describe and compare only. Do not comment on the look or on how the pieces go together.`;
}

function schemaFor(wardrobe) {
  const { kinds, chapters, colours, patterns, materials } = lists.load();
  return {
    type: 'object',
    properties: {
      pieces: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            description: { type: 'string' },
            kind: { type: 'string', enum: kinds.map((kind) => kind.name) },
            chapter: { type: 'string', enum: chapters.map((chapter) => chapter.name) },
            colours: { type: 'array', items: { type: 'string', enum: colours } },
            pattern: { type: 'string', enum: patterns },
            material: { type: 'string', enum: materials },
            shape: { type: 'string' },
            x: { type: 'integer' },
            y: { type: 'integer' },
            closest_piece: { type: 'string', enum: [...wardrobe.map((entry) => entry.number), 'none'] },
            match: { type: 'string', enum: MATCHES },
          },
          required: ['description', 'kind', 'chapter', 'colours', 'pattern', 'material', 'shape', 'x', 'y', 'closest_piece', 'match'],
          additionalProperties: false,
        },
      },
    },
    required: ['pieces'],
    additionalProperties: false,
  };
}

// The part that asks Claude. The tests replace it, so they cost nothing.
const remote = {
  async claude({ prompt, schema }) {
    return ask({ model: 'sonnet', system: lookPhoto.SYSTEM, prompt, schema, effort: 'medium' });
  },
};

const percent = (value) => (Number.isFinite(Number(value)) ? Math.min(100, Math.max(0, Math.round(Number(value)))) : null);

// Keeps only what can be trusted from the answer. A piece of the member's that is not in the
// same chapter as the described piece is not its match (a bag is never the closest to a coat).
// With no piece of the member's, the match is missing.
function checked(answer, wardrobe) {
  const { kindByName, colours } = lists.load();
  const byNumber = new Map(wardrobe.map((entry) => [entry.number, entry.piece]));
  const pieces = [];
  for (const item of Array.isArray(answer?.pieces) ? answer.pieces : []) {
    const description = lookPhoto.shortName(item?.description);
    if (!description) continue;
    const kind = kindByName.get(item?.kind) ?? null;
    let mine = byNumber.get(String(item?.closest_piece)) ?? null;
    if (mine && (!kind || kindByName.get(mine.kind)?.chapter !== kind.chapter)) mine = null;
    let match = MATCHES.includes(item?.match) ? item.match : 'missing';
    if (!mine) match = 'missing';
    const colour = Array.isArray(item?.colours) ? item.colours.find((c) => colours.includes(c)) ?? null : null;
    pieces.push({
      description: description[0].toUpperCase() + description.slice(1),
      kind: kind?.name ?? null,
      colour,
      shape: typeof item?.shape === 'string' ? item.shape.trim().slice(0, 80) || null : null,
      pinX: percent(item?.x),
      pinY: percent(item?.y),
      matchedPieceId: mine?.id ?? null,
      match,
    });
    if (pieces.length === MAX_PIECES) break;
  }
  return pieces;
}

function findInspiration(userId, id) {
  const inspirationId = Number(id);
  if (!Number.isInteger(inspirationId)) return null;
  return db.prepare('SELECT * FROM inspirations WHERE id = ? AND user_id = ?').get(inspirationId, userId) ?? null;
}

// Reads one inspiration: asks Claude and saves the pieces it found. Counts one AI action.
// If Claude cannot answer, the inspiration is "not read" and the member can try again.
async function readInspiration(inspiration) {
  const userId = inspiration.user_id;
  try {
    allowance.check(userId);
    const photo = await photos.photoForClaude(inspiration.photo_path, PHOTO_SIZE);
    const wardrobe = lookPhoto.wardrobeOf(userId);
    const prompt = [
      ...(wardrobe.length ? await lookPhoto.wardrobeBlocks(wardrobe) : [{ type: 'text', text: 'My wardrobe is empty.' }]),
      lookPhoto.imageBlock(photo),
      { type: 'text', text: instructions() },
    ];
    recordAiAction(userId, 'inspiration');
    const answer = await remote.claude({ prompt, schema: schemaFor(wardrobe) });
    savePieces(inspiration, checked(answer, wardrobe));
  } catch (error) {
    console.error(`Reading inspiration ${inspiration.id} failed: ${error.message}`);
    db.prepare(`UPDATE inspirations SET status = 'not read' WHERE id = ? AND status = 'reading'`).run(inspiration.id);
  }
}

function savePieces(inspiration, pieces) {
  db.transaction(() => {
    // Deleted by the member while Claude was reading: nothing to save.
    const still = db.prepare(`SELECT 1 FROM inspirations WHERE id = ? AND status = 'reading'`).get(inspiration.id);
    if (!still) return;
    db.prepare('DELETE FROM inspiration_pieces WHERE inspiration_id = ?').run(inspiration.id);
    const add = db.prepare(
      `INSERT INTO inspiration_pieces (user_id, inspiration_id, number, description, kind, colour, shape, pin_x, pin_y, matched_piece_id, match)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    pieces.forEach((p, i) =>
      add.run(inspiration.user_id, inspiration.id, i + 1, p.description, p.kind, p.colour, p.shape, p.pinX, p.pinY, p.matchedPieceId, p.match)
    );
    db.prepare(`UPDATE inspirations SET status = 'ready' WHERE id = ?`).run(inspiration.id);
  })();
}

// --- The member's version ---

const piecesOf = db.prepare('SELECT * FROM inspiration_pieces WHERE inspiration_id = ? AND user_id = ? ORDER BY number');
const countedPiece = db.prepare(`SELECT * FROM pieces WHERE id = ? AND user_id = ? AND status IN ('confirmed', 'maybe')`);

// The member's piece standing in for this one in their version, or null: their own choice
// first, else Claude's match when it is yours or close. A missing piece has none.
function ownPieceFor(row) {
  if (row.filled_piece_id) return countedPiece.get(row.filled_piece_id, row.user_id) ?? null;
  if (row.match !== 'missing' && row.matched_piece_id) return countedPiece.get(row.matched_piece_id, row.user_id) ?? null;
  return null;
}

// "4 of 5 yours": pieces Claude marked yours, and pieces the member filled with their own.
// Close does not count as yours (PRD section 8). Removed pieces are left out.
function counts(rows) {
  const kept = rows.filter((row) => !row.removed);
  const yours = kept.filter((row) => (row.filled_piece_id ? ownPieceFor(row) : row.match === 'yours' && ownPieceFor(row)));
  return { owned: yours.length, total: kept.length };
}

// The fact, not advice: in how many of the member's inspirations a piece like this one is
// missing (the same kind and main colour). Null when it is only this one.
function inspirationsWithPiece(userId, row) {
  if (!row.kind) return null;
  const count = db
    .prepare(
      `SELECT COUNT(DISTINCT inspiration_pieces.inspiration_id) FROM inspiration_pieces
       JOIN inspirations ON inspirations.id = inspiration_pieces.inspiration_id
       WHERE inspiration_pieces.user_id = ? AND inspirations.status = 'ready' AND inspiration_pieces.removed = 0
         AND inspiration_pieces.match = 'missing' AND inspiration_pieces.filled_piece_id IS NULL
         AND inspiration_pieces.kind = ? AND inspiration_pieces.colour IS ?`
    )
    .pluck()
    .get(userId, row.kind, row.colour);
  return count >= 2 ? count : null;
}

function photoUrl(inspiration, which) {
  const file = which === 'thumb' ? inspiration.thumb_path : inspiration.photo_path;
  const version = path.basename(file).split('-')[0];
  return `/me/inspirations/${inspiration.id}/photo/${which}?v=${version}`;
}

// Where it came from, in words, from its link: "Pinterest", "Instagram", or the site's name.
function sourceOf(link) {
  if (!link) return null;
  try {
    const host = new URL(link).hostname.replace(/^www\./, '');
    if (host === 'pin.it' || /(^|\.)pinterest\./.test(host)) return 'Pinterest';
    if (/(^|\.)instagram\.com$/.test(host)) return 'Instagram';
    return host;
  } catch {
    return null;
  }
}

function lookNumber(userId, lookId) {
  if (!lookId) return null;
  return db.prepare('SELECT number FROM looks WHERE id = ? AND user_id = ?').pluck().get(lookId, userId) ?? null;
}

// One inspiration for the home grid.
function summaryJSON(inspiration) {
  const rows = piecesOf.all(inspiration.id, inspiration.user_id);
  return {
    id: inspiration.id,
    status: inspiration.status,
    thumb: photoUrl(inspiration, 'thumb'),
    occasion: inspiration.occasion_id,
    ...counts(rows),
    createdAt: inspiration.created_at,
  };
}

// One inspiration for its page: your version.
function inspirationJSON(inspiration) {
  const userId = inspiration.user_id;
  const rows = piecesOf.all(inspiration.id, userId);
  return {
    id: inspiration.id,
    status: inspiration.status,
    photo: photoUrl(inspiration, 'photo'),
    thumb: photoUrl(inspiration, 'thumb'),
    link: inspiration.link,
    source: sourceOf(inspiration.link),
    note: inspiration.note,
    occasion: inspiration.occasion_id,
    look: inspiration.look_id ? { id: inspiration.look_id, number: lookNumber(userId, inspiration.look_id) } : null,
    ...counts(rows),
    pieces: rows.map((row) => {
      const own = ownPieceFor(row);
      const nearest = !own && row.matched_piece_id ? countedPiece.get(row.matched_piece_id, userId) : null;
      const missing = !own;
      return {
        number: row.number,
        description: row.description,
        kind: row.kind,
        colour: row.colour,
        shape: row.shape,
        pin: row.pin_x !== null && row.pin_y !== null ? { x: row.pin_x, y: row.pin_y } : null,
        // yours, close or missing as Claude saw it; "filled" when the member chose their own piece.
        match: row.filled_piece_id && own ? 'filled' : missing ? 'missing' : row.match,
        piece: own ? pieceJSON(own) : null,
        nearest: nearest ? pieceJSON(nearest) : null,
        inspirations: missing ? inspirationsWithPiece(userId, row) : null,
        key: row.is_key === 1,
        removed: row.removed === 1,
      };
    }),
    createdAt: inspiration.created_at,
  };
}

// The To find list: missing pieces the member marked as key, newest first.
function toFindJSON(userId) {
  const rows = db
    .prepare(
      `SELECT to_find.*, inspiration_pieces.*, to_find.id AS to_find_id, to_find.status AS to_find_status,
              inspirations.id AS inspiration_id
       FROM to_find
       JOIN inspiration_pieces ON inspiration_pieces.id = to_find.inspiration_piece_id
       JOIN inspirations ON inspirations.id = inspiration_pieces.inspiration_id
       WHERE to_find.user_id = ? AND to_find.status != 'dropped'
       ORDER BY to_find.created_at DESC, to_find.id DESC`
    )
    .all(userId);
  return rows.map((row) => ({
    id: row.to_find_id,
    inspiration: row.inspiration_id,
    number: row.number,
    description: row.description,
    kind: row.kind,
    // considering, bought (T11)
    status: row.to_find_status,
    searchedAt: row.searched_at,
    inspirations: inspirationsWithPiece(userId, row),
  }));
}

// For a look saved from an inspiration: that inspiration, and its pieces still missing in the
// version (kept, and not filled with one of the member's own). Null for any other look.
function lookInspiration(userId, lookId) {
  const found = db.prepare('SELECT * FROM inspirations WHERE look_id = ? AND user_id = ?').get(lookId, userId);
  if (!found) return null;
  const missing = piecesOf
    .all(found.id, userId)
    .filter((row) => !row.removed && !ownPieceFor(row))
    .map((row) => {
      const toFind = db.prepare('SELECT status, searched_at FROM to_find WHERE inspiration_piece_id = ?').get(row.id);
      return {
        number: row.number,
        description: row.description,
        key: row.is_key === 1,
        searchedAt: toFind?.searched_at ?? null,
      };
    });
  return {
    inspiration: { id: found.id, thumb: photoUrl(found, 'thumb'), link: found.link, source: sourceOf(found.link) },
    missing,
  };
}

// --- Changes the member makes ---

// Marks a missing piece as key, or takes the mark off. Key puts it on To find.
function setKey(userId, row, key) {
  if (key) {
    db.prepare('UPDATE inspiration_pieces SET is_key = 1 WHERE id = ?').run(row.id);
    db.prepare(
      `INSERT INTO to_find (user_id, inspiration_piece_id, created_at) VALUES (?, ?, ?) ON CONFLICT (inspiration_piece_id) DO NOTHING`
    ).run(userId, row.id, iso(now()));
  } else {
    db.prepare('UPDATE inspiration_pieces SET is_key = 0 WHERE id = ?').run(row.id);
    db.prepare('DELETE FROM to_find WHERE inspiration_piece_id = ? AND user_id = ?').run(row.id, userId);
  }
}

// Changes one piece of an inspiration: { piece: id or null, removed, key }, each optional.
// - piece: the member's own piece for it (fills a missing one, or changes the match); null
//   goes back to Claude's match
// - removed: takes it out of the version, or puts it back
// - key: only a missing piece can be key
// Returns null when fine, or the error to show.
function changePiece(userId, inspiration, number, body) {
  const row = db
    .prepare('SELECT * FROM inspiration_pieces WHERE inspiration_id = ? AND user_id = ? AND number = ?')
    .get(inspiration.id, userId, Number(number));
  if (!row) return { status: 404, error: 'This piece is no longer in the inspiration.' };

  // Any refusal undoes the whole change.
  class Refused extends Error {}
  try {
    db.transaction(() => {
      if ('piece' in body) {
        if (body.piece === null) {
          db.prepare('UPDATE inspiration_pieces SET filled_piece_id = NULL WHERE id = ?').run(row.id);
        } else {
          const piece = countedPiece.get(Number(body.piece), userId);
          if (!piece) throw new Refused('This piece is no longer in your wardrobe.');
          db.prepare('UPDATE inspiration_pieces SET filled_piece_id = ? WHERE id = ?').run(piece.id, row.id);
          // Filled with one of the member's own: no longer something to find.
          setKey(userId, row, false);
        }
      }
      if ('removed' in body) {
        const removed = body.removed === true;
        db.prepare('UPDATE inspiration_pieces SET removed = ? WHERE id = ?').run(removed ? 1 : 0, row.id);
        if (removed) setKey(userId, row, false);
      }
      if ('key' in body) {
        const current = db.prepare('SELECT * FROM inspiration_pieces WHERE id = ?').get(row.id);
        if (body.key === true && (current.removed || ownPieceFor(current))) throw new Refused('Only a missing piece can be key.');
        setKey(userId, current, body.key === true);
      }
    })();
  } catch (error) {
    if (error instanceof Refused) return { status: 400, error: error.message };
    throw error;
  }
  return null;
}

// The member's version as a look's pieces: their own piece for each kept piece, each once.
function versionPieceIds(userId, inspiration) {
  const ids = piecesOf
    .all(inspiration.id, userId)
    .filter((row) => !row.removed)
    .map((row) => ownPieceFor(row)?.id)
    .filter(Boolean);
  return [...new Set(ids)];
}

// Deletes an inspiration's photo files; its rows go with it (ON DELETE CASCADE), To find too.
function removePhotoFiles(inspiration) {
  photos.removeFiles({ photo: inspiration.photo_path, thumb: inspiration.thumb_path });
}

module.exports = {
  remote,
  checked,
  schemaFor,
  readInspiration,
  findInspiration,
  summaryJSON,
  inspirationJSON,
  toFindJSON,
  lookInspiration,
  changePiece,
  versionPieceIds,
  removePhotoFiles,
  sourceOf,
};
