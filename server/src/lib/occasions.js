// Each member's own occasions (PRD sections 5 and 6), onboarding step 5 and Settings.
//
// Caro proposes four (the proposed_occasions table). A new member starts with them, then
// keeps the ones that fit, renames any, removes any or adds their own: one to eight.
// No AI is involved: occasions are always the member's choice.
// Every function takes the member's own id and touches only their rows.

const db = require('../db');

const MAXIMUM = 8;        // the Looks screen shows them as a row of words
const MAXIMUM_LENGTH = 30;
const MAXIMUM_LINE = 80;  // the short line under an occasion's name

function proposals() {
  return db.prepare('SELECT name, description FROM proposed_occasions ORDER BY position').all();
}

// A new member starts with Caro's four. Does nothing if they already have occasions.
function proposeFor(userId) {
  if (db.prepare('SELECT 1 FROM occasions WHERE user_id = ?').get(userId)) return;
  const add = db.prepare('INSERT INTO occasions (user_id, name, description, position) VALUES (?, ?, ?, ?)');
  proposals().forEach((proposal, index) => add.run(userId, proposal.name, proposal.description, index + 1));
}

// The member's occasions in order, each with its line (empty when there is none).
function occasionsFor(userId) {
  return db
    .prepare('SELECT id, name, description FROM occasions WHERE user_id = ? ORDER BY position')
    .all(userId);
}

function proposalsJSON() {
  return proposals().map((p) => ({ name: p.name, description: p.description }));
}

// Checks the list the member saved: [{ id?, name, description? }], in order.
// Returns { occasions } or { error }. An id must be one of the member's own occasions; no id
// means a new one. A new one with one of Caro's names and no line gets Caro's line.
function checkOccasions(input, userId) {
  if (!Array.isArray(input) || input.length === 0) return { error: 'Keep at least one occasion.' };
  if (input.length > MAXIMUM) return { error: 'Up to eight occasions.' };

  const own = new Set(db.prepare('SELECT id FROM occasions WHERE user_id = ?').pluck().all(userId));
  const lines = new Map(proposals().map((p) => [p.name.toLowerCase(), p.description]));
  const occasions = input.map((o) => {
    const id = o?.id === undefined || o?.id === null ? null : Number(o.id);
    const name = String(o?.name ?? '').trim();
    const line = String(o?.description ?? '').trim();
    const description = line || (id === null ? lines.get(name.toLowerCase()) ?? null : null);
    return { id, name, description };
  });

  if (occasions.some((o) => !o.name)) return { error: 'Every occasion needs a name.' };
  if (occasions.some((o) => o.name.length > MAXIMUM_LENGTH)) return { error: 'Keep occasion names to 30 letters.' };
  if (occasions.some((o) => o.description && o.description.length > MAXIMUM_LINE)) {
    return { error: 'Keep the line under an occasion to 80 letters.' };
  }
  if (new Set(occasions.map((o) => o.name.toLowerCase())).size !== occasions.length) {
    return { error: 'Give each occasion its own name.' };
  }
  const ids = occasions.filter((o) => o.id !== null).map((o) => o.id);
  if (ids.some((id) => !own.has(id)) || new Set(ids).size !== ids.length) {
    return { error: 'This occasion is no longer in your list. Open the screen again.' };
  }
  return { occasions };
}

// Saves a checked list. Occasions kept keep their id and line (a rename keeps its pieces and looks),
// the ones left out are deleted (and taken off pieces and looks), new ones are added.
function saveOccasions(userId, occasions) {
  const keep = new Set(occasions.filter((o) => o.id !== null).map((o) => o.id));
  const existing = db.prepare('SELECT id FROM occasions WHERE user_id = ?').pluck().all(userId);
  const remove = db.prepare('DELETE FROM occasions WHERE id = ? AND user_id = ?');
  existing.filter((id) => !keep.has(id)).forEach((id) => remove.run(id, userId));

  // Names are unique per member, so swapping two names needs a stop in between.
  const park = db.prepare('UPDATE occasions SET name = ? WHERE id = ? AND user_id = ?');
  occasions.forEach((o) => {
    if (o.id !== null) park.run(`occasion ${o.id} renaming`, o.id, userId);
  });

  const update = db.prepare('UPDATE occasions SET name = ?, description = ?, position = ? WHERE id = ? AND user_id = ?');
  const add = db.prepare('INSERT INTO occasions (user_id, name, description, position) VALUES (?, ?, ?, ?)');
  occasions.forEach((o, i) => {
    if (o.id !== null) update.run(o.name, o.description, i + 1, o.id, userId);
    else add.run(userId, o.name, o.description, i + 1);
  });
}

module.exports = { MAXIMUM, proposeFor, occasionsFor, proposalsJSON, checkOccasions, saveOccasions };
