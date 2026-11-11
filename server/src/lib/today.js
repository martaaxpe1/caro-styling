// The date and time for everything the server stores and checks.
//
// In development, DEV_TODAY (a date like 2026-10-30) pretends it is that day, so seasons
// and expiry dates can be tested. The time of day stays real, so rows still sort in order.
// Online, DEV_TODAY is ignored.
//
// Always use now() from here, never SQLite's own clock or new Date(), so DEV_TODAY works everywhere.

const isProduction = process.env.NODE_ENV === 'production';

function readDevToday() {
  const value = (process.env.DEV_TODAY || '').trim();
  if (!value) return null;

  if (isProduction) {
    console.warn('DEV_TODAY is ignored online. Using the real date.');
    return null;
  }

  // A real day in the form 2026-10-30. 2026-02-31 is refused.
  const day = new Date(`${value}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(day.getTime()) || iso(day).slice(0, 10) !== value) {
    throw new Error(`DEV_TODAY must be a date like 2026-10-30, not "${value}".`);
  }
  return value;
}

// A date as text for the database, in UTC, like 2026-11-10T21:30:00Z.
function iso(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

const devToday = readDevToday();

function now() {
  const real = new Date();
  if (!devToday) return real;
  // DEV_TODAY's date with the real time of day.
  return new Date(`${devToday}T${real.toISOString().slice(11)}`);
}

// Lengths of time in milliseconds, to add to a date: new Date(now().getTime() + 15 * MINUTE).
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

module.exports = { now, iso, devToday, MINUTE, HOUR, DAY };
