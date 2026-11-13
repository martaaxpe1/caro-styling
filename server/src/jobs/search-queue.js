// The queue that runs store searches in the background (Find it, PRD sections 7 and 8, T11).
//
// Marking a piece as key, or Find it, answers at once; Claude takes half a minute or more to
// search the member's stores. The app asks the server every few seconds until it is done.
// Like the inspiration queue, the state is the database: every To find piece with search
// status 'searching' is waiting, and a restart picks them up again.

const db = require('../db');
const { runSearch } = require('../lib/store-search');

// How many searches run at the same time.
const AT_ONCE = 2;

const waiting = [];
const queued = new Set();
let running = 0;
const idleWaiters = [];

function add(toFindId) {
  if (queued.has(toFindId)) return;
  queued.add(toFindId);
  waiting.push(toFindId);
  next();
}

function next() {
  while (running < AT_ONCE && waiting.length > 0) {
    const id = waiting.shift();
    running += 1;
    search(id).finally(() => {
      running -= 1;
      queued.delete(id);
      next();
    });
  }
  if (running === 0 && waiting.length === 0) {
    idleWaiters.splice(0).forEach((resolve) => resolve());
  }
}

async function search(id) {
  const toFind = db.prepare(`SELECT * FROM to_find WHERE id = ? AND search_status = 'searching'`).get(id);
  if (toFind) await runSearch(toFind);
}

// When the server starts: the searches that were still waiting when it stopped.
function start() {
  const ids = db.prepare(`SELECT id FROM to_find WHERE search_status = 'searching' ORDER BY id`).pluck().all();
  if (ids.length) console.log(`Running ${ids.length} store ${ids.length === 1 ? 'search' : 'searches'} left from before.`);
  ids.forEach(add);
}

// For the tests: resolves when nothing is waiting or running.
function idle() {
  if (running === 0 && waiting.length === 0) return Promise.resolve();
  return new Promise((resolve) => idleWaiters.push(resolve));
}

module.exports = { add, start, idle };
