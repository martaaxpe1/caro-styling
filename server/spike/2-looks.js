// npm run spike:looks
// Test 2: which of my pieces am I wearing in this photo?
// Each model gets the wardrobe (small photos and details of the 15 pieces) and one look photo.
// The wardrobe part is the same for every look, so from the second look on it is read from
// the cache at a discount. The answers are scored against answers.json, if it exists.
//
// Options:
//   --model opus,haiku   only these models (default: all three)
//   --text-only          send the wardrobe as details only, without the small photos
//   --effort low         think less (default medium)

const { ask, pickModels, describeError, MODELS } = require('./lib/claude');
const { loadFolder, imageBlock } = require('./lib/images');
const { saveJson, loadJson, loadAnswers, readOptions, dollars } = require('./lib/output');
const { WARDROBE_SYSTEM, loadWardrobe, wardrobeBlocks } = require('./lib/wardrobe');
const C = require('./lib/categories');

const INSTRUCTIONS = `The photo above shows me wearing a look. Which pieces from my wardrobe am I wearing?

worn: each wardrobe piece you can see me wearing, best matches first, with how certain you are:
- high: clearly the same piece
- medium: probably the same piece
- low: it could be, but you cannot tell
Only list pieces you can see in the photo. Each piece in the photo matches at most one wardrobe piece.

not_in_wardrobe: anything I am wearing that is not in my wardrobe, with its kind and a short description in sentence case, like "White cotton t-shirt".

photo_quality: how well the photo shows the clothes.`;

function schemaFor(wardrobe) {
  return {
    type: 'object',
    properties: {
      worn: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            piece: { type: 'string', enum: wardrobe.map((piece) => piece.number) },
            certainty: { type: 'string', enum: ['high', 'medium', 'low'] },
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
            kind: { type: 'string', enum: C.KIND_NAMES },
            description: { type: 'string' },
          },
          required: ['kind', 'description'],
          additionalProperties: false,
        },
      },
      photo_quality: { type: 'string', enum: ['clear', 'partly hidden', 'too dark', 'blurry'] },
    },
    required: ['worn', 'not_in_wardrobe', 'photo_quality'],
    additionalProperties: false,
  };
}

// Compares the pieces a model spotted with the pieces Marta says she wears.
function score(spotted, expected) {
  if (!expected) return null;
  const want = expected.map((n) => String(n).padStart(2, '0'));
  return {
    expected: want,
    found: spotted.filter((n) => want.includes(n)),
    missed: want.filter((n) => !spotted.includes(n)),
    extra: spotted.filter((n) => !want.includes(n)),
  };
}

async function main() {
  const options = readOptions();
  const models = pickModels(options.model);
  const effort = options.effort || 'medium';
  const withPhotos = !options['text-only'];
  const mode = withPhotos ? 'photos' : 'text only';

  const wardrobe = await loadWardrobe(options.wardrobe);
  const looks = await loadFolder('looks', 1568);
  if (looks.length === 0) {
    console.error('No photos in server/spike/photos/looks/ yet.');
    process.exit(1);
  }
  const answers = loadAnswers().looks || {};
  if (Object.keys(answers).length === 0) {
    console.log('No answer key yet, so the results are not scored. Tell Claude which pieces you wear in each look.');
  }

  const results = loadJson('looks.json', { modes: {} });
  results.modes[mode] = results.modes[mode] || {};
  const blocks = wardrobeBlocks(wardrobe, { withPhotos });
  const schema = schemaFor(wardrobe);

  for (const model of models) {
    console.log(`\n${MODELS[model].label}, wardrobe sent as ${mode}, effort ${effort}`);
    const run = [];
    for (const look of looks) {
      const key = String(Number(look.number));
      try {
        const answer = await ask({
          test: '2-looks',
          action: withPhotos ? 'look from a photo' : 'look from a photo (text only)',
          model,
          effort,
          system: WARDROBE_SYSTEM,
          content: [...blocks, imageBlock(look), { type: 'text', text: INSTRUCTIONS }],
          schema,
          note: `${wardrobe.length} pieces`,
        });
        const d = answer.data;
        const spotted = d ? d.worn.map((w) => w.piece) : [];
        const result = score(spotted, answers[key]);
        run.push({
          number: look.number,
          file: look.file,
          data: d,
          refused: answer.refused,
          score: result,
          seconds: answer.seconds,
          cost: answer.cost,
          usage: answer.usage,
        });

        const worn = d ? d.worn.map((w) => `${w.piece} (${w.certainty})`).join(', ') || 'none' : answer.refused ? 'declined' : 'no answer';
        const others = d && d.not_in_wardrobe.length ? `; also: ${d.not_in_wardrobe.map((p) => p.description).join(', ')}` : '';
        console.log(`  Look ${key}: ${worn}${others}`);
        if (result) {
          console.log(`    found ${result.found.length} of ${result.expected.length}, missed ${result.missed.join(', ') || 'none'}, extra ${result.extra.join(', ') || 'none'}`);
        }
        const cached = answer.usage.cacheRead ? `, ${answer.usage.cacheRead} tokens from the cache` : '';
        console.log(`    ${answer.seconds.toFixed(1)} s, ${dollars(answer.cost)}${cached}`);
      } catch (error) {
        run.push({ number: look.number, file: look.file, error: describeError(error) });
        console.log(`  Look ${key} failed: ${describeError(error)}`);
      }
    }
    results.modes[mode][model] = run;
    saveJson('looks.json', results);
  }

  console.log('\nSaved to server/spike/results/looks.json. Next: npm run spike:review');
}

main();
