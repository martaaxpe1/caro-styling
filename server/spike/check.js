// npm run spike:check
// Checks that everything is ready: the API key works, the three models answer,
// and each photo folder holds the right number of photos that can be read.
// Costs nothing: it only asks Claude which models exist.

const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { MODELS, getClient, describeError } = require('./lib/claude');
const { FOLDERS, listPhotos, prepare, visualTokens } = require('./lib/images');
const { PHOTOS_DIR } = require('./lib/output');
const { THUMB_SIZE } = require('./lib/wardrobe');

async function checkKey() {
  if (!process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_API_KEY.trim() === '') {
    console.log('API key: not found. Open server/.env and add a line: ANTHROPIC_API_KEY= followed by your key.');
    return false;
  }
  console.log('API key: found in server/.env');
  for (const model of Object.values(MODELS)) {
    try {
      await getClient().models.retrieve(model.id);
      console.log(`  ${model.label}: ready`);
    } catch (error) {
      console.log(`  ${model.label}: ${describeError(error)}`);
    }
  }
  return true;
}

// Warns when a photo came out sideways: the camera's orientation says it should be
// portrait (or landscape) but the copy is the other way round.
async function sideways(photo, copy) {
  try {
    const meta = await sharp(photo.source).metadata();
    if (!meta.width || !meta.height) return false;
    const turned = (meta.orientation || 1) >= 5;
    const shouldBePortrait = turned ? meta.width > meta.height : meta.height > meta.width;
    const isPortrait = copy.height > copy.width;
    return meta.width !== meta.height && shouldBePortrait !== isPortrait;
  } catch {
    return false; // sharp cannot read this file's details; nothing to compare
  }
}

async function checkPhotos() {
  console.log('');
  console.log(`Photos, in ${path.relative(process.cwd(), PHOTOS_DIR)}/`);
  for (const [folder, expected] of Object.entries(FOLDERS)) {
    const photos = listPhotos(folder);
    const mark = photos.length === expected ? 'ready' : `expected ${expected}`;
    console.log(`  ${folder}/: ${photos.length} photos (${mark})`);
    for (const photo of photos) {
      try {
        const copy = await prepare(photo, 1568);
        if (folder === 'pieces') await prepare(photo, THUMB_SIZE);
        const tokens = visualTokens(copy.width, copy.height);
        const warning = (await sideways(photo, copy)) ? '  may be sideways, check on the review page' : '';
        console.log(`    ${photo.number} ${photo.file}: ${copy.width} by ${copy.height}, about ${tokens} tokens${warning}`);
      } catch (error) {
        console.log(`    ${photo.number} ${photo.file}: could not be read (${error.message})`);
      }
    }
  }

  const answers = path.join(PHOTOS_DIR, 'answers.json');
  console.log(`  answers.json: ${fs.existsSync(answers) ? 'found' : 'not yet (comes after test 1)'}`);
}

async function main() {
  await checkKey();
  await checkPhotos();
}

main();
