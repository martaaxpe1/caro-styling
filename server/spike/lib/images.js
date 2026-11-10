// Finds Marta's photos and makes the copies that are sent to Claude:
// upright, no bigger than the size asked for, as JPEG, and with all metadata
// (location included) removed. sharp drops metadata unless told to keep it.
//
// iPhone photos are often HEIC, which sharp cannot read. Those are first turned
// into a JPEG with sips, the image tool built into macOS, then go through sharp.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const sharp = require('sharp');
const { PHOTOS_DIR, RESULTS_DIR, ensureDir } = require('./output');

// How many photos each folder should hold.
const FOLDERS = { pieces: 15, looks: 5, inspirations: 5 };

const EXTENSIONS = ['.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp'];

// The photos in one folder, in name order, numbered 01, 02, 03...
function listPhotos(folder) {
  const dir = path.join(PHOTOS_DIR, folder);
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((file) => !file.startsWith('.') && EXTENSIONS.includes(path.extname(file).toLowerCase()))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
    .map((file, index) => ({
      folder,
      file,
      number: String(index + 1).padStart(2, '0'),
      source: path.join(dir, file),
    }));
}

function shrink(input, size) {
  return sharp(input)
    .rotate() // turns the photo upright, using the orientation the camera saved
    .resize({ width: size, height: size, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85 })
    .toBuffer({ resolveWithObject: true });
}

// Makes (or reuses) the copy of one photo at the given size, in results/prepared/.
async function prepare(photo, size) {
  const outDir = path.join(RESULTS_DIR, 'prepared', String(size), photo.folder);
  const out = path.join(outDir, photo.file + '.jpg');

  let data;
  let info;
  if (fs.existsSync(out) && fs.statSync(out).mtimeMs >= fs.statSync(photo.source).mtimeMs) {
    data = fs.readFileSync(out);
    info = await sharp(data).metadata();
  } else {
    try {
      ({ data, info } = await shrink(photo.source, size));
    } catch {
      const tmp = path.join(os.tmpdir(), `caro-spike-${process.pid}-${Date.now()}.jpg`);
      execFileSync('sips', ['-s', 'format', 'jpeg', photo.source, '--out', tmp], { stdio: 'ignore' });
      try {
        ({ data, info } = await shrink(tmp, size));
      } finally {
        fs.rmSync(tmp, { force: true });
      }
    }
    ensureDir(outDir);
    fs.writeFileSync(out, data);
  }

  return {
    ...photo,
    path: out,
    width: info.width,
    height: info.height,
    base64: data.toString('base64'),
  };
}

// All photos of one folder, prepared at one size.
async function loadFolder(folder, size) {
  const prepared = [];
  for (const photo of listPhotos(folder)) {
    prepared.push(await prepare(photo, size));
  }
  return prepared;
}

// The block that puts one image into a message. cache marks the end of a part
// that stays the same between calls, so Claude can reuse it at a discount.
function imageBlock(image, { cache = false } = {}) {
  const block = {
    type: 'image',
    source: { type: 'base64', media_type: 'image/jpeg', data: image.base64 },
  };
  if (cache) block.cache_control = { type: 'ephemeral' };
  return block;
}

// What an image costs in tokens: one token per 28 by 28 pixel square.
function visualTokens(width, height) {
  return Math.ceil(width / 28) * Math.ceil(height / 28);
}

module.exports = { FOLDERS, listPhotos, prepare, loadFolder, imageBlock, visualTokens };
