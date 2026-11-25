// A member's pieces as the app sees them (PRD sections 6 and 8).
// Every function takes the member's own id and touches only their rows.

const path = require('path');
const db = require('../db');
const lists = require('./lists');

// One of the member's pieces, or null: an id that is not theirs is the same as no piece.
function findPiece(userId, id) {
  const pieceId = Number(id);
  if (!Number.isInteger(pieceId)) return null;
  return db.prepare('SELECT * FROM pieces WHERE id = ? AND user_id = ?').get(pieceId, userId) ?? null;
}

// The address the app asks for one of a piece's pictures, or null when there is none (no cut-out).
// ?v= is part of the file's random name: a retaken photo gets a new address, so the copy the
// iPhone kept of the old one is not shown.
function imageUrl(piece, which) {
  const file = { photo: piece.original_path, cutout: piece.cutout_path, thumb: piece.thumb_path }[which];
  if (!file) return null;
  const version = path.basename(file).split('-')[0];
  return `/me/pieces/${piece.id}/${which}?v=${version}`;
}

const kindOf = db.prepare('SELECT chapter, slot FROM kinds WHERE name = ?');
const coloursOf = db.prepare('SELECT colour FROM piece_colours WHERE piece_id = ? ORDER BY position');
const seasonsOf = db.prepare(
  `SELECT piece_seasons.season_id FROM piece_seasons JOIN seasons ON seasons.id = piece_seasons.season_id
   WHERE piece_seasons.piece_id = ? ORDER BY seasons.position`
);
const occasionsOf = db.prepare(
  `SELECT piece_occasions.occasion_id FROM piece_occasions JOIN occasions ON occasions.id = piece_occasions.occasion_id
   WHERE piece_occasions.piece_id = ? ORDER BY occasions.position`
);

const looksOf = db.prepare('SELECT COUNT(*) FROM look_pieces WHERE piece_id = ?');

function pieceJSON(piece) {
  const kind = piece.kind ? kindOf.get(piece.kind) : null;
  return {
    id: piece.id,
    status: piece.status,
    detailsStatus: piece.details_status,
    name: piece.name,
    kind: piece.kind,
    chapter: kind?.chapter ?? null,
    slot: kind?.slot ?? null,
    colours: coloursOf.pluck().all(piece.id),
    pattern: piece.pattern,
    material: piece.material,
    warmth: piece.warmth,
    formality: piece.formality,
    brand: piece.brand,
    notes: piece.notes,
    // False: the member marked it as not fitting yet (T13).
    fits: piece.fits === 1,
    seasons: seasonsOf.pluck().all(piece.id),
    // New seasons proposed after the member changed their year, not checked yet (PRD section 8).
    seasonsToCheck: piece.seasons_to_check === 1,
    // How many of the member's looks it is in.
    looks: looksOf.pluck().get(piece.id),
    occasions: occasionsOf.pluck().all(piece.id),
    images: {
      photo: imageUrl(piece, 'photo'),
      cutout: imageUrl(piece, 'cutout'),
      thumb: imageUrl(piece, 'thumb'),
    },
    // The store's name when its photo is still the store's picture (Bought, T11).
    storePhoto: piece.store_photo ?? null,
    createdAt: piece.created_at,
    confirmedAt: piece.confirmed_at,
  };
}

// Checks the details the member saved in the review queue: { name, kind, colours, pattern,
// material, warmth, formality, seasons, occasions, status }, and optionally brand, notes and fits.
// Returns { details } or { error }.
// Every value must be on its fixed list; seasons and occasions must be the member's own.
function checkDetails(body, userId) {
  const { kindByName, colours, patterns, materials, warmth, formality } = lists.load();
  const name = String(body?.name ?? '').trim();
  if (!name) return { error: 'Name this piece.' };
  if (name.length > 60) return { error: 'Keep the name to 60 letters.' };
  if (!kindByName.has(body?.kind)) return { error: 'Choose what kind of piece this is.' };

  const pieceColours = Array.isArray(body?.colours) ? body.colours : [];
  if (pieceColours.length > 3 || new Set(pieceColours).size !== pieceColours.length || pieceColours.some((c) => !colours.includes(c))) {
    return { error: 'Choose up to three colours from the list.' };
  }

  const optional = (value, list) => value === null || value === undefined || list.includes(value);
  if (!optional(body?.pattern, patterns) || !optional(body?.material, materials)) {
    return { error: 'Choose the pattern and material from the list.' };
  }
  if (!optional(body?.warmth, warmth) || !optional(body?.formality, formality)) {
    return { error: 'Choose the warmth and formality from the list.' };
  }

  const ids = (value) => (Array.isArray(value) ? [...new Set(value.map(Number))] : []);
  const seasons = ids(body?.seasons);
  const occasions = ids(body?.occasions);
  const ownSeasons = new Set(db.prepare('SELECT id FROM seasons WHERE user_id = ?').pluck().all(userId));
  const ownOccasions = new Set(db.prepare('SELECT id FROM occasions WHERE user_id = ?').pluck().all(userId));
  if (seasons.some((id) => !ownSeasons.has(id))) return { error: 'This season is no longer in your year. Open the piece again.' };
  if (occasions.some((id) => !ownOccasions.has(id))) return { error: 'This occasion is no longer in your list. Open the piece again.' };

  if (!['confirmed', 'maybe'].includes(body?.status)) return { error: 'Confirm the piece or mark it as maybe.' };

  // Brand and notes are optional. Left out of the request: unchanged. Empty: cleared.
  const brand = optionalText(body, 'brand');
  const notes = optionalText(body, 'notes');
  if (brand?.length > 40) return { error: 'Keep the brand to 40 letters.' };
  if (notes?.length > 280) return { error: 'Keep the note to 280 letters.' };

  // Doesn't fit yet (T13). Left out, as an older app does: unchanged.
  if (body.fits !== undefined && typeof body.fits !== 'boolean') return { error: 'Say whether this piece fits.' };

  return {
    details: {
      name: name[0].toUpperCase() + name.slice(1),
      kind: body.kind,
      colours: pieceColours,
      pattern: body.pattern ?? null,
      material: body.material ?? null,
      warmth: body.warmth ?? null,
      formality: body.formality ?? null,
      seasons,
      occasions,
      status: body.status,
      brand,
      notes,
      fits: body.fits,
    },
  };
}

// undefined when the request leaves the field out, null when it is empty, or the text.
function optionalText(body, field) {
  if (!body || !(field in body)) return undefined;
  const text = String(body[field] ?? '').trim();
  return text || null;
}

// Marks a piece as not fitting yet, or as fitting again (T13).
function setFits(piece, fits) {
  db.prepare('UPDATE pieces SET fits = ? WHERE id = ? AND user_id = ?').run(fits ? 1 : 0, piece.id, piece.user_id);
}

// Saves checked details. A piece the member confirms before Claude finished reading it
// keeps the member's details: Claude's answer is no longer wanted.
const saveDetails = db.transaction((piece, d, at) => {
  db.prepare(
    `UPDATE pieces SET name = ?, kind = ?, pattern = ?, material = ?, warmth = ?, formality = ?, status = ?,
       confirmed_at = COALESCE(confirmed_at, ?),
       details_status = CASE details_status WHEN 'reading' THEN 'not read' ELSE details_status END,
       seasons_to_check = 0
     WHERE id = ? AND user_id = ?`
  ).run(d.name, d.kind, d.pattern, d.material, d.warmth, d.formality, d.status, at, piece.id, piece.user_id);
  if (d.brand !== undefined) db.prepare('UPDATE pieces SET brand = ? WHERE id = ? AND user_id = ?').run(d.brand, piece.id, piece.user_id);
  if (d.notes !== undefined) db.prepare('UPDATE pieces SET notes = ? WHERE id = ? AND user_id = ?').run(d.notes, piece.id, piece.user_id);
  if (d.fits !== undefined) setFits(piece, d.fits);

  db.prepare('DELETE FROM piece_colours WHERE piece_id = ? AND user_id = ?').run(piece.id, piece.user_id);
  const addColour = db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, ?)');
  d.colours.forEach((colour, index) => addColour.run(piece.user_id, piece.id, colour, index + 1));

  db.prepare('DELETE FROM piece_seasons WHERE piece_id = ? AND user_id = ?').run(piece.id, piece.user_id);
  const addSeason = db.prepare('INSERT INTO piece_seasons (user_id, piece_id, season_id) VALUES (?, ?, ?)');
  d.seasons.forEach((id) => addSeason.run(piece.user_id, piece.id, id));

  db.prepare('DELETE FROM piece_occasions WHERE piece_id = ? AND user_id = ?').run(piece.id, piece.user_id);
  const addOccasion = db.prepare('INSERT INTO piece_occasions (user_id, piece_id, occasion_id) VALUES (?, ?, ?)');
  d.occasions.forEach((id) => addOccasion.run(piece.user_id, piece.id, id));
});

module.exports = { findPiece, imageUrl, pieceJSON, checkDetails, saveDetails, setFits };
