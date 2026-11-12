// The queue that reads new pieces in the background (PRD sections 5 and 8).
//
// Adding a piece answers the app at once; reading its details takes Claude a few seconds.
// So each new piece is put in this queue, and the queue asks Claude for a few at a time while
// the member keeps adding photos. The app asks the server every few seconds which are ready.
//
// The queue's state is the database itself: every piece with details_status 'reading' is
// waiting. When the server starts, it picks them up again, so a restart loses nothing.

const db = require('../db');
const { readPiece } = require('../lib/piece-details');

// How many pieces Claude reads at the same time.
const AT_ONCE = 3;

const waiting = [];      // piece ids, in the order they arrived
const queued = new Set(); // the same ids, to never read a piece twice
let running = 0;
const idleWaiters = [];

function add(pieceId) {
  if (queued.has(pieceId)) return;
  queued.add(pieceId);
  waiting.push(pieceId);
  next();
}

function next() {
  while (running < AT_ONCE && waiting.length > 0) {
    const pieceId = waiting.shift();
    running += 1;
    read(pieceId).finally(() => {
      running -= 1;
      queued.delete(pieceId);
      next();
    });
  }
  if (running === 0 && waiting.length === 0) {
    idleWaiters.splice(0).forEach((resolve) => resolve());
  }
}

async function read(pieceId) {
  const piece = db.prepare(`SELECT * FROM pieces WHERE id = ? AND details_status = 'reading'`).get(pieceId);
  if (piece) await readPiece(piece);
}

// When the server starts: the pieces that were still waiting when it stopped.
function start() {
  const ids = db.prepare(`SELECT id FROM pieces WHERE details_status = 'reading' ORDER BY id`).pluck().all();
  if (ids.length) console.log(`Reading the details of ${ids.length} ${ids.length === 1 ? 'piece' : 'pieces'} left from before.`);
  ids.forEach(add);
}

// For the tests: resolves when nothing is waiting or being read.
function idle() {
  if (running === 0 && waiting.length === 0) return Promise.resolve();
  return new Promise((resolve) => idleWaiters.push(resolve));
}

module.exports = { add, start, idle };
