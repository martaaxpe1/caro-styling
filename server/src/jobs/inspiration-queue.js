// The queue that reads new inspirations in the background (PRD sections 7 and 8, T10).
//
// Adding an inspiration answers at once, so the share sheet on the iPhone can close; Claude
// takes some seconds to describe the pieces. The app asks the server every few seconds until
// the inspiration is ready. Like the piece queue (piece-queue.js), the state is the database:
// every inspiration with status 'reading' is waiting, and a restart picks them up again.

const db = require('../db');
const { readInspiration } = require('../lib/inspiration');

// How many inspirations Claude reads at the same time.
const AT_ONCE = 2;

const waiting = [];
const queued = new Set();
let running = 0;
const idleWaiters = [];

function add(inspirationId) {
  if (queued.has(inspirationId)) return;
  queued.add(inspirationId);
  waiting.push(inspirationId);
  next();
}

function next() {
  while (running < AT_ONCE && waiting.length > 0) {
    const id = waiting.shift();
    running += 1;
    read(id).finally(() => {
      running -= 1;
      queued.delete(id);
      next();
    });
  }
  if (running === 0 && waiting.length === 0) {
    idleWaiters.splice(0).forEach((resolve) => resolve());
  }
}

async function read(id) {
  const inspiration = db.prepare(`SELECT * FROM inspirations WHERE id = ? AND status = 'reading'`).get(id);
  if (inspiration) await readInspiration(inspiration);
}

// When the server starts: the inspirations that were still waiting when it stopped.
function start() {
  const ids = db.prepare(`SELECT id FROM inspirations WHERE status = 'reading' ORDER BY id`).pluck().all();
  if (ids.length) console.log(`Reading ${ids.length} ${ids.length === 1 ? 'inspiration' : 'inspirations'} left from before.`);
  ids.forEach(add);
}

// For the tests: resolves when nothing is waiting or being read.
function idle() {
  if (running === 0 && waiting.length === 0) return Promise.resolve();
  return new Promise((resolve) => idleWaiters.push(resolve));
}

module.exports = { add, start, idle };
