// Look from a photo (PRD sections 7, 8 and 10, screen S9): which of the member's own pieces
// are they wearing in this photo?
//
// The prompt and the answer form are the ones the T1 spike tested (server/spike/2-looks.js,
// docs/SPIKE.md test 2): Sonnet gets the member's wardrobe (each counted piece as a small
// picture and one line of details) and the photo, and says which pieces it sees and how sure
// it is. The form only allows the numbers of the member's own pieces, so Claude can never
// name a piece from someone else's wardrobe, or invent one.
//
// Claude only recognises. It never says what goes with what, and it never completes a look:
// the member confirms every piece. A piece it is less sure of is asked about, not ticked.

const sharp = require('sharp');
const db = require('../db');
const photos = require('./photos');
const { ask, recordAiAction } = require('./claude');
const { pieceJSON } = require('./pieces');
const lists = require('./lists');

const PHOTO_SIZE = 1568;
// The wardrobe's small pictures, as in the spike.
const THUMB_SIZE = 512;
// Cut-outs have a transparent background: Claude sees them on Caro's tile colour.
const TILE = '#EFE7DB';

const SYSTEM = `You help a person keep track of the clothes they already own.
You recognise clothing in photos and match it to pieces in their wardrobe.
You only recognise and describe. You never suggest outfits or looks, never say what goes with what, never rate or judge style or taste, and never recommend buying anything.
When you are not sure, say so through the certainty fields instead of guessing.`;

const INSTRUCTIONS = `The photo above shows me wearing a look. Which pieces from my wardrobe am I wearing?

worn: each wardrobe piece you can see me wearing, best matches first, with how certain you are:
- high: clearly the same piece
- medium: probably the same piece
- low: it could be, but you cannot tell
Only list pieces you can see in the photo. Each piece in the photo matches at most one wardrobe piece.

not_in_wardrobe: anything I am wearing that is not in my wardrobe, with its kind and a short name of 2 to 5 words in sentence case, like "White cotton t-shirt".

photo_quality: how well the photo shows the clothes.`;

const CERTAINTIES = ['high', 'medium', 'low'];
const PHOTO_QUALITIES = ['clear', 'partly hidden', 'too dark', 'blurry'];

// The member's counted pieces that have a kind: what Claude may choose from. Each gets a
// number for the prompt, 1 to N, so the answer never shows database ids.
function wardrobeOf(userId) {
  const pieces = db
    .prepare(
      `SELECT pieces.* FROM pieces JOIN kinds ON kinds.name = pieces.kind
       WHERE pieces.user_id = ? AND pieces.status IN ('confirmed', 'maybe') ORDER BY pieces.id`
    )
    .all(userId);
  return pieces.map((piece, index) => ({ number: String(index + 1), piece }));
}

const coloursOf = db.prepare('SELECT colour FROM piece_colours WHERE piece_id = ? ORDER BY position');

function pieceLine({ number, piece }) {
  const colours = coloursOf.pluck().all(piece.id).join(' and ') || 'not known';
  return `Piece ${number}: ${piece.name || 'No name'}. Kind: ${piece.kind}. Colours: ${colours}. Pattern: ${piece.pattern || 'not known'}. Material: ${piece.material || 'not known'}.`;
}

// A piece's small picture for Claude, or null if its file cannot be read (then Claude gets
// its line of details only).
async function thumbForClaude(piece) {
  const file = piece.cutout_path || piece.original_path || piece.thumb_path;
  if (!file) return null;
  try {
    const bytes = await sharp(photos.absolute(file))
      .rotate()
      .resize({ width: THUMB_SIZE, height: THUMB_SIZE, fit: 'inside', withoutEnlargement: true })
      .flatten({ background: TILE })
      .jpeg({ quality: 80 })
      .toBuffer();
    return bytes.toString('base64');
  } catch {
    return null;
  }
}

function imageBlock(base64) {
  return { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: base64 } };
}

// The message: the wardrobe first (the same for every photo of this member, so a second
// photo soon after reads it from Anthropic's cache at a discount), then the photo.
async function promptFor(wardrobe, photoBase64) {
  const blocks = [{ type: 'text', text: `These are the ${wardrobe.length} pieces in my wardrobe.` }];
  for (const entry of wardrobe) {
    blocks.push({ type: 'text', text: pieceLine(entry) });
    const thumb = await thumbForClaude(entry.piece);
    if (thumb) blocks.push(imageBlock(thumb));
  }
  blocks[blocks.length - 1].cache_control = { type: 'ephemeral' };
  blocks.push(imageBlock(photoBase64));
  blocks.push({ type: 'text', text: INSTRUCTIONS });
  return blocks;
}

function schemaFor(wardrobe) {
  return {
    type: 'object',
    properties: {
      worn: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            piece: { type: 'string', enum: wardrobe.map((entry) => entry.number) },
            certainty: { type: 'string', enum: CERTAINTIES },
          },
          required: ['piece', 'certainty'],
          additionalProperties: false,
        },
      },
      not_in_wardrobe: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            kind: { type: 'string', enum: lists.load().kinds.map((kind) => kind.name) },
            description: { type: 'string' },
          },
          required: ['kind', 'description'],
          additionalProperties: false,
        },
      },
      photo_quality: { type: 'string', enum: PHOTO_QUALITIES },
    },
    required: ['worn', 'not_in_wardrobe', 'photo_quality'],
    additionalProperties: false,
  };
}

// The part that asks Claude. The tests replace it, so they cost nothing.
const remote = {
  async claude({ prompt, schema }) {
    return ask({ model: 'sonnet', system: SYSTEM, prompt, schema, effort: 'medium' });
  },
};

// Keeps only what can be trusted from the answer: the member's own pieces, each once, best
// first. A piece is ticked when Claude is sure (high or medium) and its slot is still free;
// otherwise it is asked about ("Is this your pale pink t-shirt?").
function checked(answer, wardrobe) {
  const byNumber = new Map(wardrobe.map((entry) => [entry.number, entry.piece]));
  const seen = new Set();
  const spotted = [];
  for (const item of Array.isArray(answer?.worn) ? answer.worn : []) {
    const piece = byNumber.get(String(item?.piece));
    if (!piece || seen.has(piece.id)) continue;
    seen.add(piece.id);
    spotted.push({ piece, certainty: CERTAINTIES.includes(item.certainty) ? item.certainty : 'low' });
  }
  // Sure ones first, in Claude's order within each.
  spotted.sort((a, b) => CERTAINTIES.indexOf(a.certainty) - CERTAINTIES.indexOf(b.certainty));

  const taken = new Set();
  const result = spotted.map(({ piece, certainty }) => {
    const json = pieceJSON(piece);
    const slot = json.slot;
    // One piece per slot except accessories; a dress takes the bottom's place.
    const clash =
      slot !== 'accessories' &&
      (taken.has(slot) || (slot === 'bottom' && taken.has('one-piece')) || (slot === 'one-piece' && taken.has('bottom')));
    const ticked = certainty !== 'low' && !clash;
    if (ticked) taken.add(slot);
    return { piece: json, certainty, ticked };
  });

  const { kindByName } = lists.load();
  const notInWardrobe = (Array.isArray(answer?.not_in_wardrobe) ? answer.not_in_wardrobe : [])
    .map((item) => ({
      kind: kindByName.has(item?.kind) ? item.kind : null,
      description: shortName(item?.description),
    }))
    .filter((item) => item.description)
    .map((item) => ({ ...item, description: item.description[0].toUpperCase() + item.description.slice(1) }));

  return {
    spotted: result,
    notInWardrobe: notInWardrobe.slice(0, 8),
    photoQuality: PHOTO_QUALITIES.includes(answer?.photo_quality) ? answer.photo_quality : null,
  };
}

// A short name for something not in the wardrobe: "Long-sleeved leopard print mini dress with a
// pleated skirt, ruffled cuffs and a ..." becomes "Long-sleeved leopard print mini dress".
// Cut at the first comma or "with", then at a whole word, never in the middle of one.
const NAME_LENGTH = 48;
function shortName(text) {
  let name = String(text ?? '').trim().split(/,| with /)[0].trim();
  if (name.length > NAME_LENGTH) name = name.slice(0, NAME_LENGTH + 1).replace(/\s+\S*$/, '');
  return name.replace(/[\s.;:-]+$/, '');
}

// Spots the member's pieces in a photo they sent (base64). Nothing is stored: the photo is
// saved only when the member saves the look. Counts one AI action.
async function spot(userId, photoBase64) {
  const photo = await photos.sentPhotoForClaude(photoBase64, PHOTO_SIZE);
  const wardrobe = wardrobeOf(userId);
  if (wardrobe.length === 0) return { spotted: [], notInWardrobe: [], photoQuality: null };
  const prompt = await promptFor(wardrobe, photo);
  recordAiAction(userId, 'look from a photo');
  const answer = await remote.claude({ prompt, schema: schemaFor(wardrobe) });
  return checked(answer, wardrobe);
}

module.exports = { remote, spot, checked, wardrobeOf };
