// npm run spike:details
// Test 1: suggested details for each piece photo, from each model.
//
// Options:
//   --model opus,haiku   only these models (default: all three)
//   --size 1024          send smaller photos (default 1568 pixels on the long side)
//   --effort medium      think longer before answering (default low)

const { ask, pickModels, describeError, MODELS } = require('./lib/claude');
const { loadFolder, imageBlock, visualTokens } = require('./lib/images');
const { saveJson, loadJson, readOptions, dollars } = require('./lib/output');
const C = require('./lib/categories');

const SYSTEM = `You help a person catalogue the clothes they already own.
You look at a photo of one piece of clothing, a pair of shoes, a bag or an accessory, and describe what you see.
You only recognise and describe. You never suggest outfits, never say what a piece goes with, never judge style or taste, and never recommend buying anything.
Write in British English, in sentence case.`;

const INSTRUCTIONS = `Describe the piece in this photo by filling in every field.

name: 2 to 4 words in sentence case, the way a person would name it in their own wardrobe, for example "Terracotta linen skirt" or "Black leather loafers". No brand names.

kind and chapter: choose the kind first, then the chapter it is listed under:
${C.kindsByChapterText()}

colours: one to three, main colour first.

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

const SCHEMA = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    kind: { type: 'string', enum: C.KIND_NAMES },
    chapter: { type: 'string', enum: C.CHAPTERS },
    colours: { type: 'array', items: { type: 'string', enum: C.COLOURS } },
    pattern: { type: 'string', enum: C.PATTERNS },
    material: { type: 'string', enum: C.MATERIALS },
    warmth: { type: 'string', enum: C.WARMTH },
    formality: { type: 'string', enum: C.FORMALITY },
    single_piece: { type: 'boolean' },
    unsure_about: {
      type: 'array',
      items: { type: 'string', enum: ['name', 'kind', 'colours', 'pattern', 'material', 'warmth', 'formality'] },
    },
  },
  required: ['name', 'kind', 'chapter', 'colours', 'pattern', 'material', 'warmth', 'formality', 'single_piece', 'unsure_about'],
  additionalProperties: false,
};

async function main() {
  const options = readOptions();
  const models = pickModels(options.model);
  const size = Number(options.size) || 1568;
  const effort = options.effort || 'low';

  const pieces = await loadFolder('pieces', size);
  if (pieces.length === 0) {
    console.error('No photos in server/spike/photos/pieces/ yet.');
    process.exit(1);
  }

  const file = `details-${size}.json`;
  const results = loadJson(file, { size, effort, runs: {} });
  results.effort = effort;

  for (const model of models) {
    console.log(`\n${MODELS[model].label}, photos at ${size} pixels, effort ${effort}`);
    const run = [];
    for (const piece of pieces) {
      try {
        const answer = await ask({
          test: '1-details',
          action: 'piece details',
          model,
          effort,
          system: SYSTEM,
          content: [imageBlock(piece), { type: 'text', text: INSTRUCTIONS }],
          schema: SCHEMA,
          note: `size ${size}`,
        });
        const d = answer.data;
        const problems = [];
        if (answer.refused) problems.push(`declined (${answer.refusalCategory || 'no reason given'})`);
        if (d && !C.kindMatchesChapter(d.kind, d.chapter)) problems.push(`kind "${d.kind}" is not in chapter "${d.chapter}"`);
        if (d && !d.single_piece) problems.push('says the photo shows more than one piece');

        run.push({
          number: piece.number,
          file: piece.file,
          image_tokens: visualTokens(piece.width, piece.height),
          data: d,
          problems,
          seconds: answer.seconds,
          cost: answer.cost,
          usage: answer.usage,
        });

        const summary = d ? `${d.name} · ${d.chapter} / ${d.kind} · ${d.colours.join(', ')} · ${d.material} · ${d.warmth} · ${d.formality}` : 'no answer';
        const flags = problems.length ? `  [${problems.join('; ')}]` : '';
        console.log(`  ${piece.number} ${summary}  (${answer.seconds.toFixed(1)} s, ${dollars(answer.cost)})${flags}`);
      } catch (error) {
        run.push({ number: piece.number, file: piece.file, error: describeError(error) });
        console.log(`  ${piece.number} failed: ${describeError(error)}`);
      }
    }
    results.runs[model] = run;
    saveJson(file, results);

    const done = run.filter((r) => r.data);
    const total = done.reduce((sum, r) => sum + r.cost, 0);
    const seconds = done.reduce((sum, r) => sum + r.seconds, 0);
    if (done.length) {
      console.log(`  Average per piece: ${dollars(total / done.length)}, ${(seconds / done.length).toFixed(1)} s`);
    }
  }

  console.log(`\nSaved to server/spike/results/${file}. Next: npm run spike:review`);
}

main();
