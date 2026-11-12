// The fixed lists, the same for every member (PRD sections 6 and 8): chapters and kinds,
// colours, patterns, materials, warmth and formality. They live in the database (migration 002),
// so the prompt, the checks and the app all use the same words.

const db = require('../db');

const WARMTH = ['light', 'medium', 'warm'];
const FORMALITY = ['casual', 'smart casual', 'smart', 'formal'];

let cached = null;

function load() {
  if (cached) return cached;
  const chapters = db.prepare('SELECT name, number FROM chapters ORDER BY number').all();
  const kinds = db.prepare('SELECT name, chapter, slot FROM kinds ORDER BY position').all();
  const names = (table) => db.prepare(`SELECT name FROM ${table} ORDER BY position`).pluck().all();

  cached = {
    chapters,
    kinds,
    kindByName: new Map(kinds.map((kind) => [kind.name, kind])),
    colours: names('colours'),
    patterns: names('patterns'),
    materials: names('materials'),
    warmth: WARMTH,
    formality: FORMALITY,
  };
  return cached;
}

// The kinds as text for a prompt, one chapter a line: "- outerwear: coat, trench coat, ..."
function kindsByChapterText() {
  const { chapters, kinds } = load();
  return chapters
    .map((chapter) => `- ${chapter.name}: ${kinds.filter((kind) => kind.chapter === chapter.name).map((kind) => kind.name).join(', ')}`)
    .join('\n');
}

// Everything the app needs to show and change a piece's details.
function listsJSON() {
  const { chapters, kinds, colours, patterns, materials, warmth, formality } = load();
  return {
    chapters: chapters.map((chapter) => ({
      name: chapter.name,
      number: chapter.number,
      kinds: kinds.filter((kind) => kind.chapter === chapter.name).map((kind) => ({ name: kind.name, slot: kind.slot })),
    })),
    colours,
    patterns,
    materials,
    warmth,
    formality,
  };
}

module.exports = { load, kindsByChapterText, listsJSON };
