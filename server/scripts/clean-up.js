// npm run clean-up
// Runs the daily clean-up by hand, the same one the server runs every 24 hours.
// To try it 31 days from now: DEV_TODAY=2026-12-15 npm run clean-up

const db = require('../src/db');
const { now, devToday } = require('../src/lib/today');
const { cleanUp, describe } = require('../src/jobs/clean-up');

console.log(`Today: ${now().toISOString().slice(0, 10)}${devToday ? ' (pretend, from DEV_TODAY)' : ''}`);
console.log(describe(cleanUp()));

db.close();
