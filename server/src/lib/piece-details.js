// Claude suggests the details of a new piece from its photo (PRD sections 8 and 10).
//
// The prompt and the form are the ones the T1 spike chose (server/spike/1-details.js,
// docs/SPIKE.md test 1): Sonnet, the photo at 1568 pixels, effort low. About 1 cent a piece.
// Claude only recognises and describes: it never says what a piece goes with.
//
// Every answer is checked against the fixed lists before it is saved, and it stays a
// suggestion: the member confirms or changes it in the review queue.

const db = require('../db');
const lists = require('./lists');
const photos = require('./photos');
const { ask, recordAiAction } = require('./claude');
const allowance = require('./allowance');
const pieceSeasons = require('./piece-seasons');
const places = require('./places');
const weather = require('./weather');

const PHOTO_SIZE = 1568;

const SYSTEM = `You help a person catalogue the clothes they already own.
You look at a photo of one piece of clothing, a pair of shoes, a bag or an accessory, and describe what you see.
You only recognise and describe. You never suggest outfits, never say what a piece goes with, never judge style or taste, and never recommend buying anything.
Write in British English, in sentence case.`;

function instructions() {
  return `Describe the piece in this photo by filling in every field.

name: 2 to 4 words in sentence case, the way a person would name it in their own wardrobe, for example "Terracotta linen skirt" or "Black leather loafers". No brand names.

kind and chapter: choose the kind first, then the chapter it is listed under:
${lists.kindsByChapterText()}

colours: one to three, main colour first. Only the colours you see on the outside of the piece when it is worn: leave out linings, insoles, soles, labels and the inside of a bag.

pattern and material: what you can see. Use "not sure" for material when the photo does not show it.

warmth, meaning the weather the piece is made for, the same anywhere in the world:
- light: for warm days, such as linen, thin cotton, silk, sandals
- medium: for most of the year, such as denim, cotton knits, light jackets, trainers
- warm: for cold days, such as wool coats, thick knits, lined boots

formality:
- casual: everyday and relaxed, such as t-shirts, jeans, trainers
- smart casual: neat but relaxed, such as a shirt, a knit, loafers
- smart: office or a dinner, such as tailored trousers, a blazer, heels
- formal: special occasions, such as an evening dress

single_piece: false if the photo shows more than one piece. A pair of shoes, a pair of earrings or a set sold together counts as one piece. If there is more than one piece, describe the main one.

unsure_about: the fields you could not tell well from the photo, if any.`;
}

function schema() {
  const { kinds, chapters, colours, patterns, materials, warmth, formality } = lists.load();
  return {
    type: 'object',
    properties: {
      name: { type: 'string' },
      kind: { type: 'string', enum: kinds.map((kind) => kind.name) },
      chapter: { type: 'string', enum: chapters.map((chapter) => chapter.name) },
      colours: { type: 'array', items: { type: 'string', enum: colours } },
      pattern: { type: 'string', enum: patterns },
      material: { type: 'string', enum: materials },
      warmth: { type: 'string', enum: warmth },
      formality: { type: 'string', enum: formality },
      single_piece: { type: 'boolean' },
      unsure_about: {
        type: 'array',
        items: { type: 'string', enum: ['name', 'kind', 'colours', 'pattern', 'material', 'warmth', 'formality'] },
      },
    },
    required: ['name', 'kind', 'chapter', 'colours', 'pattern', 'material', 'warmth', 'formality', 'single_piece', 'unsure_about'],
    additionalProperties: false,
  };
}

// The part that asks Claude. The tests replace it, so they cost nothing.
const remote = {
  async claude(photoBase64) {
    return ask({
      model: 'sonnet',
      system: SYSTEM,
      prompt: [
        { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: photoBase64 } },
        { type: 'text', text: instructions() },
      ],
      schema: schema(),
      effort: 'low',
    });
  },
};

// Only values from the fixed lists are kept; anything else is left for the member to fill in.
function checked(answer) {
  const { kindByName, colours, patterns, materials, warmth, formality } = lists.load();
  const pick = (value, list) => (list.includes(value) ? value : null);
  const name = String(answer?.name ?? '').trim().slice(0, 60);
  const pieceColours = [...new Set((answer?.colours ?? []).filter((colour) => colours.includes(colour)))].slice(0, 3);
  return {
    name: name ? name[0].toUpperCase() + name.slice(1) : null,
    kind: kindByName.has(answer?.kind) ? answer.kind : null,
    colours: pieceColours,
    pattern: pick(answer?.pattern, patterns),
    material: pick(answer?.material, materials),
    warmth: pick(answer?.warmth, warmth),
    formality: pick(answer?.formality, formality),
  };
}

const saveSuggestion = db.transaction((piece, details) => {
  // The member may have removed the piece while Claude was reading it.
  const stillThere = db.prepare(`SELECT 1 FROM pieces WHERE id = ? AND user_id = ? AND details_status = 'reading'`).get(piece.id, piece.user_id);
  if (!stillThere) return;

  db.prepare(
    `UPDATE pieces SET name = ?, kind = ?, pattern = ?, material = ?, warmth = ?, formality = ?, details_status = 'suggested'
     WHERE id = ? AND user_id = ?`
  ).run(details.name, details.kind, details.pattern, details.material, details.warmth, details.formality, piece.id, piece.user_id);

  db.prepare('DELETE FROM piece_colours WHERE piece_id = ? AND user_id = ?').run(piece.id, piece.user_id);
  const addColour = db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, ?)');
  details.colours.forEach((colour, index) => addColour.run(piece.user_id, piece.id, colour, index + 1));

  if (details.warmth) pieceSeasons.proposeForPiece(piece.user_id, piece.id, details.warmth);
});

function markNotRead(piece) {
  db.prepare(`UPDATE pieces SET details_status = 'not read' WHERE id = ? AND user_id = ? AND details_status = 'reading'`).run(piece.id, piece.user_id);
}

// Seasons are proposed from the city's typical weather. A member set up before T4 (like the
// seeded admin) may not have it yet: look it up once, the same way Your year does.
// Three pieces are read at once, so they share one look-up instead of starting three.
const weatherLookups = new Map();

function ensureWeather(userId) {
  if (!weatherLookups.has(userId)) {
    weatherLookups.set(userId, lookUpWeather(userId).finally(() => weatherLookups.delete(userId)));
  }
  return weatherLookups.get(userId);
}

async function lookUpWeather(userId) {
  const member = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  const hasSeasons = db.prepare('SELECT 1 FROM seasons WHERE user_id = ?').get(userId);
  if (!member || !hasSeasons || !(member.city_id || member.city)) return;
  if (member.city_id && db.prepare('SELECT 1 FROM city_weather WHERE city_id = ?').get(member.city_id)) return;
  try {
    const city = await places.cityForMember(member);
    if (city) await weather.typicalWeather(city, userId);
  } catch (error) {
    console.error(`Weather for proposing seasons failed: ${error.message}`);
  }
}

// Reads one piece: asks Claude, checks the answer, saves it as a suggestion.
// If Claude cannot answer, the piece is "not read" and the member fills in the details.
async function readPiece(piece) {
  // The month's AI allowance is used up: the piece is kept, and the member fills in its details.
  if (!allowance.hasRoom(piece.user_id)) {
    markNotRead(piece);
    return;
  }
  try {
    const photo = await photos.photoForClaude(piece.original_path, PHOTO_SIZE);
    // Counted when asked: each piece is one AI action this month (PRD section 10).
    recordAiAction(piece.user_id, 'piece details');
    const answer = await remote.claude(photo);
    await ensureWeather(piece.user_id);
    saveSuggestion(piece, checked(answer));
  } catch (error) {
    // Removed by the member while it was being read: nothing to do.
    if (!db.prepare('SELECT 1 FROM pieces WHERE id = ?').get(piece.id)) return;
    console.error(`Details for piece ${piece.id} failed: ${error.message}`);
    markNotRead(piece);
  }
}

module.exports = { remote, readPiece, checked };
