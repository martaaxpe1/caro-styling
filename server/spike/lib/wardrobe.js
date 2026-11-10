// The wardrobe as tests 2 and 3 see it: each piece's number, a small photo and its details.
// The details come from test 1, with Marta's corrections on top, standing in for the
// details a member confirms in the review queue.

const { loadJson, loadAnswers } = require('./output');
const { loadFolder, imageBlock } = require('./images');

const THUMB_SIZE = 512;

// The standing instructions for tests 2 and 3. They are the same in both, so the
// wardrobe that follows them can be reused from the cache across both tests.
const WARDROBE_SYSTEM = `You help a person keep track of the clothes they already own.
You recognise clothing in photos and match it to pieces in their wardrobe.
You only recognise and describe. You never suggest outfits or looks, never say what goes with what, never rate or judge style or taste, and never recommend buying anything.
When you are not sure, say so through the certainty fields instead of guessing.`;

async function loadWardrobe(source = 'opus') {
  const details = loadJson('details-1568.json', null);
  if (!details || Object.keys(details.runs).length === 0) {
    console.error('Tests 2 and 3 use the details from test 1. Run it first: npm run spike:details');
    process.exit(1);
  }
  const run = details.runs[source] || Object.values(details.runs)[0];
  const corrections = loadAnswers().pieces || {};
  const thumbs = await loadFolder('pieces', THUMB_SIZE);

  return thumbs.map((thumb) => {
    const fromTest1 = run.find((result) => result.file === thumb.file);
    return {
      number: thumb.number,
      file: thumb.file,
      thumb,
      details: { ...(fromTest1 && fromTest1.data), ...(corrections[thumb.number] || {}) },
    };
  });
}

function pieceLine(piece) {
  const d = piece.details;
  const colours = (d.colours || []).join(' and ');
  return `Piece ${piece.number}: ${d.name}. Kind: ${d.kind}. Colours: ${colours}. Pattern: ${d.pattern}. Material: ${d.material}.`;
}

// The wardrobe part of a message. withPhotos false sends the details only, to compare.
function wardrobeBlocks(wardrobe, { withPhotos = true } = {}) {
  const blocks = [{ type: 'text', text: `These are the ${wardrobe.length} pieces in my wardrobe.` }];
  wardrobe.forEach((piece, index) => {
    const last = index === wardrobe.length - 1;
    const line = { type: 'text', text: pieceLine(piece) };
    if (last && !withPhotos) line.cache_control = { type: 'ephemeral' };
    blocks.push(line);
    if (withPhotos) blocks.push(imageBlock(piece.thumb, { cache: last }));
  });
  return blocks;
}

module.exports = { THUMB_SIZE, WARDROBE_SYSTEM, loadWardrobe, pieceLine, wardrobeBlocks };
