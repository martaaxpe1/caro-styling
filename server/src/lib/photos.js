// Piece photos on the server's disk (PRD sections 8, 11 and 14).
//
// The app sends two pictures for each piece: the photo, and the cut-out the iPhone made of it
// (none when nothing lifted). From them, sharp, the image tool, makes three files:
// - the photo: upright, at most 2000 pixels on the long side, as JPEG
// - the cut-out: the piece on a transparent background, as WebP (a small format that keeps
//   the transparency; iPhones read it)
// - the thumbnail: 600 pixels, from the cut-out, or from the photo when nothing lifted
//
// sharp drops every hidden note in a photo file (EXIF: camera, date, and where it was taken)
// unless it is told to keep them. Nothing here tells it to, so no location data is stored.
//
// The files live in DATA_DIR/photos/<member id>/, outside Git, with random names. They are
// never public: the app gets them only through signed-in requests (src/routes/pieces.js).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require('sharp');
const { dataDir } = require('./paths');

const PHOTO_SIZE = 2000;
const THUMB_SIZE = 600;

// Something was wrong with a picture the app sent. The message is safe to show in the app.
class PhotoError extends Error {}

// Paths in the database are relative to DATA_DIR, so the folder can move (Render's disk, T8).
function absolute(relativePath) {
  return path.join(dataDir, relativePath);
}

function memberFolder(userId) {
  return path.join('photos', String(userId));
}

// The app sends each picture as base64: the bytes of the file written as text.
function decode(base64) {
  if (typeof base64 !== 'string' || base64.length === 0) return null;
  const bytes = Buffer.from(base64, 'base64');
  return bytes.length > 0 ? bytes : null;
}

function fitInside(size) {
  return { width: size, height: size, fit: 'inside', withoutEnlargement: true };
}

// Saves the three files for one piece and returns their paths, relative to DATA_DIR:
// { original, cutout (or null), thumb }.
async function savePiecePhotos(userId, { photo, cutout }) {
  const photoBytes = decode(photo);
  if (!photoBytes) throw new PhotoError('The photo did not arrive. Try again.');
  const cutoutBytes = cutout ? decode(cutout) : null;

  // A random name for each upload, so a retaken photo never has the old one's address.
  const name = crypto.randomBytes(12).toString('hex');
  const folder = memberFolder(userId);
  fs.mkdirSync(absolute(folder), { recursive: true });

  const files = {
    original: path.join(folder, `${name}-photo.jpg`),
    cutout: cutoutBytes ? path.join(folder, `${name}-cutout.webp`) : null,
    thumb: path.join(folder, `${name}-thumb.webp`),
  };

  try {
    // rotate() with no angle turns the photo upright, using the orientation the camera saved.
    await sharp(photoBytes).rotate().resize(fitInside(PHOTO_SIZE)).jpeg({ quality: 85, mozjpeg: true }).toFile(absolute(files.original));
    if (cutoutBytes) {
      await sharp(cutoutBytes).rotate().resize(fitInside(PHOTO_SIZE)).webp({ quality: 90 }).toFile(absolute(files.cutout));
    }
    await sharp(cutoutBytes ?? photoBytes).rotate().resize(fitInside(THUMB_SIZE)).webp({ quality: 80 }).toFile(absolute(files.thumb));
  } catch (error) {
    removeFiles(files);
    console.error(`A piece photo could not be saved: ${error.message}`);
    throw new PhotoError('Caro could not read this photo. Try another one.');
  }
  return files;
}

// Saves a photo of the member wearing a look (T9): the photo, upright, at most 2000 pixels,
// as JPEG, and a 600 pixel thumbnail as WebP. Like piece photos, no location data is kept.
// Returns { photo, thumb }, relative to DATA_DIR.
async function saveLookPhoto(userId, base64) {
  return savePhotoAndThumb(userId, decode(base64), 'look');
}

// Saves an inspiration's photo (T10), the same way as a look photo. `image` is base64 from
// the app, or the bytes of an image the server fetched from a Pinterest link.
async function saveInspirationPhoto(userId, image) {
  return savePhotoAndThumb(userId, Buffer.isBuffer(image) ? image : decode(image), 'inspiration');
}

// A photo and its thumbnail, named "<random>-<label>.jpg" and "<random>-<label>-thumb.webp".
async function savePhotoAndThumb(userId, bytes, label) {
  if (!bytes || bytes.length === 0) throw new PhotoError('The photo did not arrive. Try again.');
  const name = crypto.randomBytes(12).toString('hex');
  const folder = memberFolder(userId);
  fs.mkdirSync(absolute(folder), { recursive: true });
  const files = {
    photo: path.join(folder, `${name}-${label}.jpg`),
    thumb: path.join(folder, `${name}-${label}-thumb.webp`),
  };
  try {
    await sharp(bytes).rotate().resize(fitInside(PHOTO_SIZE)).jpeg({ quality: 85, mozjpeg: true }).toFile(absolute(files.photo));
    await sharp(bytes).rotate().resize(fitInside(THUMB_SIZE)).webp({ quality: 80 }).toFile(absolute(files.thumb));
  } catch (error) {
    removeFiles(files);
    console.error(`A ${label} photo could not be saved: ${error.message}`);
    throw new PhotoError('Caro could not read this photo. Try another one.');
  }
  return files;
}

// A photo the app sent, as Claude gets it: upright, at most `size` pixels, JPEG, as base64.
// Nothing is written to the disk.
async function sentPhotoForClaude(base64, size) {
  const bytes = decode(base64);
  if (!bytes) throw new PhotoError('The photo did not arrive. Try again.');
  try {
    const out = await sharp(bytes).rotate().resize(fitInside(size)).jpeg({ quality: 85 }).toBuffer();
    return out.toString('base64');
  } catch {
    throw new PhotoError('Caro could not read this photo. Try another one.');
  }
}

// Turns a piece's pictures a quarter turn clockwise, for a photo taken sideways. The turned
// pictures get a new name, so the iPhone shows them instead of the copies it kept.
// Returns the new paths; the caller deletes the old files.
async function rotatePiecePhotos(userId, files) {
  const name = crypto.randomBytes(12).toString('hex');
  const folder = memberFolder(userId);
  const turned = {
    original: path.join(folder, `${name}-photo.jpg`),
    cutout: files.cutout ? path.join(folder, `${name}-cutout.webp`) : null,
    thumb: path.join(folder, `${name}-thumb.webp`),
  };
  try {
    await sharp(absolute(files.original)).rotate(90).jpeg({ quality: 90, mozjpeg: true }).toFile(absolute(turned.original));
    if (files.cutout) {
      await sharp(absolute(files.cutout)).rotate(90).webp({ quality: 90 }).toFile(absolute(turned.cutout));
    }
    await sharp(absolute(files.thumb)).rotate(90).webp({ quality: 80 }).toFile(absolute(turned.thumb));
  } catch (error) {
    removeFiles(turned);
    console.error(`A piece photo could not be turned: ${error.message}`);
    throw new PhotoError('Caro could not turn this photo. Try again.');
  }
  return turned;
}

// The photo as Claude gets it: upright, at most `size` pixels, JPEG, as base64.
async function photoForClaude(originalPath, size) {
  const bytes = await sharp(absolute(originalPath)).resize(fitInside(size)).jpeg({ quality: 85 }).toBuffer();
  return bytes.toString('base64');
}

// Deletes the files of one piece: { original, cutout, thumb }, or the paths of a pieces row.
function removeFiles(files) {
  for (const file of Object.values(files)) {
    if (file) fs.rmSync(absolute(file), { force: true });
  }
}

function filesOf(piece) {
  return { original: piece.original_path, cutout: piece.cutout_path, thumb: piece.thumb_path };
}

// Deletes all of a member's photos, when the member is deleted.
function removeMemberPhotos(userId) {
  fs.rmSync(absolute(memberFolder(userId)), { recursive: true, force: true });
}

module.exports = {
  PhotoError,
  absolute,
  savePiecePhotos,
  saveLookPhoto,
  saveInspirationPhoto,
  sentPhotoForClaude,
  rotatePiecePhotos,
  photoForClaude,
  removeFiles,
  filesOf,
  removeMemberPhotos,
};
