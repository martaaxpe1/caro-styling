// The monthly AI allowance (PRD sections 10 and 11), enforced here from T11.
//
// Every AI action is a row in ai_usage (recordAiAction in claude.js). A member may make as
// many as the allowance in settings (300 to start, set by the admin) in each calendar month.
// The month follows the server's clock (or DEV_TODAY), in UTC.
//
// Before any AI action the server calls check(userId). When the allowance is used up it throws
// AllowanceError, whose message the app shows as it is.

const db = require('../db');
const { now, iso } = require('./today');

class AllowanceError extends Error {}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function monthStart(at = now()) {
  return new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), 1));
}

function nextMonthStart(at = now()) {
  return new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth() + 1, 1));
}

function allowance() {
  return db.prepare('SELECT ai_monthly_allowance FROM settings WHERE id = 1').pluck().get() ?? 300;
}

function setAllowance(value) {
  db.prepare('UPDATE settings SET ai_monthly_allowance = ? WHERE id = 1').run(value);
}

function usedThisMonth(userId) {
  return db
    .prepare('SELECT COUNT(*) FROM ai_usage WHERE user_id = ? AND created_at >= ?')
    .pluck()
    .get(userId, iso(monthStart()));
}

function hasRoom(userId) {
  return usedThisMonth(userId) < allowance();
}

// "You have used this month's 300 AI actions. They start again on 1 December."
function message() {
  const next = nextMonthStart();
  const limit = allowance();
  return `You have used this month's ${limit} AI ${limit === 1 ? 'action' : 'actions'}. They start again on ${next.getUTCDate()} ${MONTHS[next.getUTCMonth()]}.`;
}

function check(userId) {
  if (!hasRoom(userId)) throw new AllowanceError(message());
}

// For the admin: this month's AI actions, all members together and by kind.
function totalsThisMonth() {
  const rows = db
    .prepare('SELECT action, COUNT(*) AS count FROM ai_usage WHERE created_at >= ? GROUP BY action ORDER BY count DESC, action')
    .all(iso(monthStart()));
  return { total: rows.reduce((sum, row) => sum + row.count, 0), byAction: rows };
}

module.exports = { AllowanceError, allowance, setAllowance, usedThisMonth, hasRoom, check, message, monthStart, totalsThisMonth };
