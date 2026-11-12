// A member's pieces as the app sees them (PRD sections 6 and 8).
// Every function takes the member's own id and touches only their rows.

const path = require('path');
const db = require('../db');

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
    seasons: seasonsOf.pluck().all(piece.id),
    occasions: occasionsOf.pluck().all(piece.id),
    images: {
      photo: imageUrl(piece, 'photo'),
      cutout: imageUrl(piece, 'cutout'),
      thumb: imageUrl(piece, 'thumb'),
    },
    createdAt: piece.created_at,
    confirmedAt: piece.confirmed_at,
  };
}

module.exports = { findPiece, imageUrl, pieceJSON };
