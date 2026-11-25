// Already in the edit (PRD sections 7, 8 and 10, T14): does a new piece look like one the
// member already has?
//
// 1. Choose: the server picks up to 12 of the member's own pieces that could be it, in the same
//    chapter, the most alike first. Free, and it keeps the question to Claude small.
// 2. Ask: Claude gets the new piece's picture and those, and says which are the same piece and
//    how sure it is. The form only allows those numbers, so it can only name the member's own.
// 3. Flag: the sure ones (high and medium), three at most, wait in piece_lookalikes. Review asks
//    about them one at a time. The member answers "same" or "different"; Caro never removes or
//    joins pieces by itself.
//
// Colour alone never decides: the same jumper is grey in one photo and brown in another.
// Every function takes the member's own id and touches only their rows.

const db = require('../db');
const { now, iso } = require('./today');
const photos = require('./photos');
const lookPhoto = require('./look-photo');
const { ask } = require('./claude');

// The new piece's picture. Larger than the others: the details that tell two pieces apart are small.
const NEW_SIZE = 1024;
const MOST_ALIKE = 12;
const MOST_FLAGS = 3;
const CERTAINTIES = ['high', 'medium', 'low'];

const SYSTEM = `You help a person keep track of the clothes they already own.
You compare photos of clothing and say whether two photos show the very same piece.
You only recognise and compare. You never suggest outfits or looks, never say what goes with what, never rate or judge style or taste, and never recommend buying anything.
When you are not sure, say so through the certainty field instead of guessing.`;

const INSTRUCTIONS = `The last picture is a new photo of one piece. Is it one of my pieces above, photographed again?

The same piece can look different in two photos: another light, another angle, folded or hung differently, partly cropped. Light shifts a colour: white can look cream or grey, navy can look black, olive can look brown. It never turns a white piece into a black one. So a colour that could be the same in another light does not settle it, and one that could not be means another piece. Compare what does not change: the cut and length, the collar, neckline, sleeves and waistband, pockets, buttons, zips and buckles, seams and quilting, the print and where it falls, the sole and the stitching.

Two different pieces can also look alike, like two plain black t-shirts of another cut. If the details that do not change differ, it is another piece.

same: each piece above that is the very same piece as the new photo, with how certain you are:
- high: clearly the same piece
- medium: probably the same piece
- low: it could be, but you cannot tell
Leave the list empty when it is none of them.`;

// --- Choose ---

// How alike two pieces are by their details: { kind, colours, pattern, material }. Only used to
// choose which ones Claude compares, so a wrong colour costs a place in line, never the answer.
function alike(a, b) {
  let score = 0;
  if (a.kind === b.kind) score += 4;
  const shared = a.colours.filter((colour) => b.colours.includes(colour)).length;
  if (shared > 0) score += 2;
  if (a.colours[0] && a.colours[0] === b.colours[0]) score += 1;
  if (a.pattern && a.pattern === b.pattern) score += a.pattern === 'plain' ? 0.5 : 2;
  if (a.material && a.material === b.material && a.material !== 'not sure') score += 1;
  return score;
}

// The most alike of these, at most 12. Equal ones stay in the order given.
function mostAlike(piece, others) {
  return others
    .map((other) => ({ other, score: alike(piece, other) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, MOST_ALIKE)
    .map(({ other }) => other);
}

const coloursOf = db.prepare('SELECT colour FROM piece_colours WHERE piece_id = ? ORDER BY position');

function detailsOf(piece) {
  return { kind: piece.kind, colours: coloursOf.pluck().all(piece.id), pattern: piece.pattern, material: piece.material };
}

// The member's own pieces that could be this one: the same chapter, in the edit or waiting for
// review, and not already asked about. The most alike first, at most 12.
function candidatesFor(piece) {
  const others = db
    .prepare(
      `SELECT pieces.* FROM pieces JOIN kinds ON kinds.name = pieces.kind
       WHERE pieces.user_id = ? AND pieces.id <> ?
         AND kinds.chapter = (SELECT chapter FROM kinds WHERE name = ?)
         AND NOT EXISTS (
           SELECT 1 FROM piece_lookalikes
           WHERE (piece_id = pieces.id AND other_id = ?) OR (piece_id = ? AND other_id = pieces.id)
         )
       ORDER BY pieces.id DESC`
    )
    .all(piece.user_id, piece.id, piece.kind, piece.id, piece.id);
  const mine = detailsOf(piece);
  return mostAlike(mine, others.map((other) => ({ ...detailsOf(other), piece: other }))).map(({ piece: other }) => other);
}

// --- Ask ---

// `wardrobe` is [{ number, piece }], as for a look from a photo.
async function promptFor(wardrobe, newPicture) {
  return [
    ...(await lookPhoto.wardrobeBlocks(wardrobe, { cache: false })),
    { type: 'text', text: 'This is the new photo.' },
    lookPhoto.imageBlock(newPicture),
    { type: 'text', text: INSTRUCTIONS },
  ];
}

function schemaFor(numbers) {
  return {
    type: 'object',
    properties: {
      same: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            piece: { type: 'string', enum: numbers },
            certainty: { type: 'string', enum: CERTAINTIES },
          },
          required: ['piece', 'certainty'],
          additionalProperties: false,
        },
      },
    },
    required: ['same'],
    additionalProperties: false,
  };
}

// The part that asks Claude. The tests replace it, so they cost nothing.
const remote = {
  async claude({ prompt, schema }) {
    return ask({ model: 'sonnet', system: SYSTEM, prompt, schema, effort: 'low' });
  },
};

// The sure ones, surest first, each once, at most three: [{ number, certainty }].
function checked(answer, numbers) {
  const seen = new Set();
  const sure = [];
  for (const item of Array.isArray(answer?.same) ? answer.same : []) {
    const number = String(item?.piece);
    if (!numbers.includes(number) || seen.has(number)) continue;
    seen.add(number);
    if (item.certainty === 'high' || item.certainty === 'medium') sure.push({ number, certainty: item.certainty });
  }
  return sure.sort((a, b) => CERTAINTIES.indexOf(a.certainty) - CERTAINTIES.indexOf(b.certainty)).slice(0, MOST_FLAGS);
}

// Compares a piece whose details were just read with the member's others, and keeps the flags.
// Part of the piece's one AI action. Throws when Claude cannot answer.
async function compare(piece) {
  const others = candidatesFor(piece);
  if (others.length === 0) return;
  const picture = await lookPhoto.pieceForClaude(piece, NEW_SIZE);
  if (!picture) return;
  const wardrobe = others.map((other, index) => ({ number: String(index + 1), piece: other }));
  const numbers = wardrobe.map((entry) => entry.number);
  const answer = await remote.claude({ prompt: await promptFor(wardrobe, picture), schema: schemaFor(numbers) });
  const sure = checked(answer, numbers).map(({ number, certainty }) => ({ otherId: others[Number(number) - 1].id, certainty }));
  saveFlags(piece, sure);
}

const findOwn = db.prepare('SELECT * FROM pieces WHERE id = ? AND user_id = ?');

// The flag is on the piece waiting for review; of two waiting, on the newer one. Two pieces
// already in the edit are not flagged: the member confirmed both while Claude was comparing.
const saveFlags = db.transaction((piece, sure) => {
  const add = db.prepare(
    `INSERT INTO piece_lookalikes (user_id, piece_id, other_id, certainty, created_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (piece_id, other_id) DO NOTHING`
  );
  for (const { otherId, certainty } of sure) {
    // Either may have been removed meanwhile.
    const pair = [findOwn.get(piece.id, piece.user_id), findOwn.get(otherId, piece.user_id)];
    if (!pair[0] || !pair[1]) continue;
    const waiting = pair.filter((one) => one.status === 'pending').sort((a, b) => b.id - a.id);
    if (waiting.length === 0) continue;
    const flagged = waiting[0];
    const other = pair.find((one) => one.id !== flagged.id);
    add.run(piece.user_id, flagged.id, other.id, certainty, iso(now()));
  }
});

// --- The member's answer ---

const GONE = { status: 404, error: 'This piece is no longer in your wardrobe.' };

// The flag the member answers: both pieces their own, the first still waiting for review, and
// not answered before. Returns { piece, other } or { status, error }.
function findFlag(userId, pieceId, otherId) {
  const piece = findOwn.get(Number(pieceId), userId);
  const other = findOwn.get(Number(otherId), userId);
  if (!piece || !other) return GONE;
  const open = db
    .prepare('SELECT 1 FROM piece_lookalikes WHERE piece_id = ? AND other_id = ? AND user_id = ? AND answer IS NULL')
    .get(piece.id, other.id, userId);
  if (!open || piece.status !== 'pending') return { status: 400, error: 'Caro is no longer asking about this piece.' };
  return { piece, other };
}

// The same piece: the one that was there first stays, with its details, seasons, occasions and
// looks, and the photo the member chose ('old' or 'new'). The new piece goes, with the photo not
// chosen. All of it or none of it; the files are deleted only after it.
// Returns { piece: the one that stays } or { status, error }.
function same(userId, pieceId, otherId, keep) {
  if (keep !== 'old' && keep !== 'new') return { status: 400, error: 'Choose the old photo or the new one.' };
  const found = findFlag(userId, pieceId, otherId);
  if (found.error) return found;
  const { piece, other } = found;

  db.transaction(() => {
    if (keep === 'new') {
      // Like Retake: a store's picture is replaced for good.
      db.prepare('UPDATE pieces SET original_path = ?, cutout_path = ?, thumb_path = ?, store_photo = NULL WHERE id = ? AND user_id = ?').run(
        piece.original_path, piece.cutout_path, piece.thumb_path, other.id, userId
      );
    }
    db.prepare('DELETE FROM pieces WHERE id = ? AND user_id = ?').run(piece.id, userId);
  })();
  photos.removeFiles(photos.filesOf(keep === 'new' ? other : piece));
  return { piece: findOwn.get(other.id, userId) };
}

// Another piece: remembered, so those two are not asked about again.
function different(userId, pieceId, otherId) {
  const found = findFlag(userId, pieceId, otherId);
  if (found.error) return found;
  db.prepare(`UPDATE piece_lookalikes SET answer = 'different' WHERE piece_id = ? AND other_id = ? AND user_id = ?`).run(
    found.piece.id, found.other.id, userId
  );
  return { piece: found.piece };
}

module.exports = {
  NEW_SIZE,
  SYSTEM,
  remote,
  alike,
  mostAlike,
  candidatesFor,
  promptFor,
  schemaFor,
  checked,
  compare,
  same,
  different,
};
