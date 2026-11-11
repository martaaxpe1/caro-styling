// Middleware: small checks that run before a route.
//
// requireMember reads the session token the app sends ("Authorization: Bearer <token>"),
// finds the member it belongs to and puts them on req.member. Every route that touches a
// member's data runs behind it and only uses req.member.id, so a member can never reach
// another member's data.
//
// requireAdmin runs after it and lets only the admin through. The app hides the admin area
// from members too, but this is the check that counts.

const db = require('../db');
const { now, iso } = require('../lib/today');
const { hashToken } = require('../lib/auth');

const findSession = db.prepare(`
  SELECT sessions.id AS session_id, users.*
  FROM sessions JOIN users ON users.id = sessions.user_id
  WHERE sessions.token_hash = ?
`);
const touchSession = db.prepare('UPDATE sessions SET last_used_at = ? WHERE id = ?');
const touchUser = db.prepare('UPDATE users SET last_active_at = ? WHERE id = ?');

function requireMember(req, res, next) {
  const header = req.get('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : '';
  const row = token ? findSession.get(hashToken(token)) : null;

  // No token, an unknown one (for example after npm run reset-dev), or access removed.
  if (!row || row.status === 'removed') {
    return res.status(401).json({ error: 'You are signed out. Sign in again.' });
  }

  // Last active, for the admin's member list.
  const at = iso(now());
  touchSession.run(at, row.session_id);
  touchUser.run(at, row.id);

  const { session_id: sessionId, ...member } = row;
  req.member = { ...member, last_active_at: at };
  req.sessionId = sessionId;
  next();
}

function requireAdmin(req, res, next) {
  if (req.member?.role !== 'admin') {
    return res.status(403).json({ error: 'Only the admin can do this.' });
  }
  next();
}

module.exports = { requireMember, requireAdmin };
