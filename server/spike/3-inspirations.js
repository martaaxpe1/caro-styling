// npm run spike:inspirations
// Test 3: describe each piece in an inspiration and find the closest piece I own
// of the same kind, marked yours, close or missing. Marta judges the matches on the review page.
//
// Options:
//   --model opus,haiku   only these models (default: all three)
//   --text-only          send the wardrobe as details only, without the small photos
//   --effort low         think less (default medium)

const { ask, pickModels, describeError, MODELS } = require('./lib/claude');
const { loadFolder, imageBlock } = require('./lib/images');
const { saveJson, loadJson, readOptions, dollars } = require('./lib/output');
const { WARDROBE_SYSTEM, loadWardrobe, wardrobeBlocks } = require('./lib/wardrobe');
const C = require('./lib/categories');

const INSTRUCTIONS = `The image above is an inspiration: a look I like. Describe each piece in it, then find the closest piece I own of the same kind.

For each piece you can see in the inspiration:
- description: a short name in sentence case, like "Grey oversized blazer"
- kind and chapter, from this list:
${C.kindsByChapterText()}
- colours (main colour first), pattern and material, from the lists. Material "not sure" when you cannot tell.
- shape: a few words on the cut or fit, like "oversized, single-breasted"
- closest_piece: the number of my piece of the same kind (or a near kind in the same chapter, like a jacket for a blazer) that is most like it, or "none"
- match:
  - yours: my piece is very much like it, with the same kind, colour and shape
  - close: my piece is the same or a near kind, but differs in colour, shape or material
  - missing: I have nothing like it. Then closest_piece is "none".

Describe and compare only. Do not comment on the look or on how the pieces go together.`;

function schemaFor(wardrobe) {
  return {
    type: 'object',
    properties: {
      pieces: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            description: { type: 'string' },
            kind: { type: 'string', enum: C.KIND_NAMES },
            chapter: { type: 'string', enum: C.CHAPTERS },
            colours: { type: 'array', items: { type: 'string', enum: C.COLOURS } },
            pattern: { type: 'string', enum: C.PATTERNS },
            material: { type: 'string', enum: C.MATERIALS },
            shape: { type: 'string' },
            closest_piece: { type: 'string', enum: [...wardrobe.map((piece) => piece.number), 'none'] },
            match: { type: 'string', enum: ['yours', 'close', 'missing'] },
          },
          required: ['description', 'kind', 'chapter', 'colours', 'pattern', 'material', 'shape', 'closest_piece', 'match'],
          additionalProperties: false,
        },
      },
    },
    required: ['pieces'],
    additionalProperties: false,
  };
}

async function main() {
  const options = readOptions();
  const models = pickModels(options.model);
  const effort = options.effort || 'medium';
  const withPhotos = !options['text-only'];
  const mode = withPhotos ? 'photos' : 'text only';

  const wardrobe = await loadWardrobe(options.wardrobe);
  const inspirations = await loadFolder('inspirations', 1568);
  if (inspirations.length === 0) {
    console.error('No images in server/spike/photos/inspirations/ yet.');
    process.exit(1);
  }

  const results = loadJson('inspirations.json', { modes: {} });
  results.modes[mode] = results.modes[mode] || {};
  const blocks = wardrobeBlocks(wardrobe, { withPhotos });
  const schema = schemaFor(wardrobe);
  const names = Object.fromEntries(wardrobe.map((piece) => [piece.number, piece.details.name]));

  for (const model of models) {
    console.log(`\n${MODELS[model].label}, wardrobe sent as ${mode}, effort ${effort}`);
    const run = [];
    for (const inspiration of inspirations) {
      const key = String(Number(inspiration.number));
      try {
        const answer = await ask({
          test: '3-inspirations',
          action: withPhotos ? 'inspiration' : 'inspiration (text only)',
          model,
          effort,
          system: WARDROBE_SYSTEM,
          content: [...blocks, imageBlock(inspiration), { type: 'text', text: INSTRUCTIONS }],
          schema,
          note: `${wardrobe.length} pieces`,
        });
        const d = answer.data;
        run.push({
          number: inspiration.number,
          file: inspiration.file,
          data: d,
          refused: answer.refused,
          seconds: answer.seconds,
          cost: answer.cost,
          usage: answer.usage,
        });

        if (d) {
          const owned = d.pieces.filter((p) => p.match !== 'missing').length;
          console.log(`  Inspiration ${key}: ${owned} of ${d.pieces.length} pieces yours or close`);
          for (const p of d.pieces) {
            const mine = p.closest_piece === 'none' ? 'not in your wardrobe' : `${p.closest_piece} ${names[p.closest_piece] || ''}`;
            console.log(`    ${p.description}: ${p.match}, ${mine}`);
          }
        } else {
          console.log(`  Inspiration ${key}: ${answer.refused ? 'declined' : 'no answer'}`);
        }
        console.log(`    ${answer.seconds.toFixed(1)} s, ${dollars(answer.cost)}${answer.usage.cacheRead ? `, ${answer.usage.cacheRead} tokens from the cache` : ''}`);
      } catch (error) {
        run.push({ number: inspiration.number, file: inspiration.file, error: describeError(error) });
        console.log(`  Inspiration ${key} failed: ${describeError(error)}`);
      }
    }
    results.modes[mode][model] = run;
    saveJson('inspirations.json', results);
  }

  console.log('\nSaved to server/spike/results/inspirations.json. Next: npm run spike:review');
}

main();
