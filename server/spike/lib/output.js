// Where the spike keeps its results, and small helpers to save, read and print them.
// Everything in results/ is ignored by Git: it is made from Marta's photos.

const fs = require('fs');
const path = require('path');

const SPIKE_DIR = path.join(__dirname, '..');
const PHOTOS_DIR = path.join(SPIKE_DIR, 'photos');
const RESULTS_DIR = path.join(SPIKE_DIR, 'results');
const COST_LOG = path.join(RESULTS_DIR, 'costs.jsonl');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function saveJson(name, data) {
  ensureDir(RESULTS_DIR);
  fs.writeFileSync(path.join(RESULTS_DIR, name), JSON.stringify(data, null, 2) + '\n');
}

function loadJson(file, fallback) {
  const full = path.isAbsolute(file) ? file : path.join(RESULTS_DIR, file);
  if (!fs.existsSync(full)) return fallback;
  return JSON.parse(fs.readFileSync(full, 'utf8'));
}

// Marta's answer key: which pieces she wears in each look, and corrections to details.
// It lives next to the photos, so it is ignored by Git too.
function loadAnswers() {
  return loadJson(path.join(PHOTOS_DIR, 'answers.json'), { pieces: {}, looks: {} });
}

// One line per call to Claude, so costs.js can add them up per action and model.
function logCost(entry) {
  ensureDir(RESULTS_DIR);
  fs.appendFileSync(COST_LOG, JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n');
}

function readCostLog() {
  if (!fs.existsSync(COST_LOG)) return [];
  return fs
    .readFileSync(COST_LOG, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

// Reads simple command line options: --model opus,haiku --size 1024 --text-only
function readOptions(argv = process.argv.slice(2)) {
  const options = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      options[key] = true;
    } else {
      options[key] = next;
      i++;
    }
  }
  return options;
}

function dollars(amount) {
  if (amount === 0) return '$0';
  if (amount < 0.01) return '$' + amount.toFixed(4);
  return '$' + amount.toFixed(3);
}

module.exports = {
  SPIKE_DIR,
  PHOTOS_DIR,
  RESULTS_DIR,
  ensureDir,
  saveJson,
  loadJson,
  loadAnswers,
  logCost,
  readCostLog,
  readOptions,
  dollars,
};
