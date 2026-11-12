// Signing in and out (PRD sections 4 and 11).
//
// 1. POST /auth/code   { email }        Only an invited or member email gets a 6-digit code.
// 2. POST /auth/verify { email, code }  A right code gives back a session token for the app.
// 3. POST /auth/sign-out                Ends this session.

const express = require('express');
const db = require('../db');
const { now, iso, MINUTE, HOUR } = require('../lib/today');
const { makeCode, hashCode, checkCode, makeToken, hashToken, cleanEmail, looksLikeEmail } = require('../lib/auth');
const email = require('../lib/email');
const { memberJSON } = require('../lib/members');
const { proposeFor } = require('../lib/occasions');
const { requireMember } = require('../middleware/signed-in');

const router = express.Router();

const CODE_MINUTES = 15;   // a code works this long
const CODE_TRIES = 5;      // wrong tries allowed on one code
const CODES_PER_HOUR = 5;  // new codes per email per hour, so the tries cannot be dodged

// The same answer for an email that was never invited and for one whose access was removed.
const NO_ACCESS = 'This email does not have access to Caro.';

// Who may sign in with this email: a member whose access was not removed, or a person
// with a pending invitation that has not expired. Anyone else: null.
function findAccess(address, at) {
  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(address);
  if (user) return user.status === 'removed' ? null : { user };

  const invitation = db
    .prepare(`SELECT * FROM invitations WHERE email = ? AND status = 'pending' AND expires_at > ?`)
    .get(address, iso(at));
  return invitation ? { invitation } : null;
}

router.post('/code', async (req, res) => {
  const address = cleanEmail(req.body?.email);
  if (!looksLikeEmail(address)) {
    return res.status(400).json({ error: 'Type your email, like name@example.com.' });
  }

  const at = now();
  if (!findAccess(address, at)) {
    return res.status(403).json({ error: NO_ACCESS });
  }

  // Codes from the last hour, up to now. With DEV_TODAY the date stays the same every day,
  // so a code asked for on another real day can carry a later time of day: it does not count.
  const lastHour = db
    .prepare('SELECT COUNT(*) FROM login_codes WHERE email = ? AND created_at > ? AND created_at <= ?')
    .pluck()
    .get(address, iso(new Date(at.getTime() - HOUR)), iso(at));
  if (lastHour >= CODES_PER_HOUR) {
    return res.status(429).json({ error: 'Too many codes for this email. Try again in an hour.' });
  }

  const code = makeCode();
  db.transaction(() => {
    // A new code replaces any earlier one that was not used.
    db.prepare('UPDATE login_codes SET expires_at = ? WHERE email = ? AND used_at IS NULL AND expires_at > ?').run(
      iso(at),
      address,
      iso(at)
    );
    db.prepare('INSERT INTO login_codes (email, code_hash, created_at, expires_at) VALUES (?, ?, ?, ?)').run(
      address,
      hashCode(code),
      iso(at),
      iso(new Date(at.getTime() + CODE_MINUTES * MINUTE))
    );
  })();

  try {
    await email.sendSignInCode(address, code, CODE_MINUTES);
  } catch (err) {
    if (err instanceof email.EmailError) return res.status(502).json({ error: err.message });
    throw err;
  }
  res.json({ ok: true });
});

router.post('/verify', (req, res) => {
  const address = cleanEmail(req.body?.email);
  const code = String(req.body?.code ?? '').replace(/\s/g, '');
  const at = now();

  // The latest code sent to this email that has not been used.
  const row = db
    .prepare('SELECT * FROM login_codes WHERE email = ? AND used_at IS NULL ORDER BY id DESC LIMIT 1')
    .get(address);

  if (!row || row.expires_at <= iso(at)) {
    return res.status(400).json({ error: 'This code has expired. Send a new one.' });
  }
  if (row.attempts >= CODE_TRIES) {
    return res.status(400).json({ error: 'Too many tries. Send a new code.' });
  }

  if (!/^\d{6}$/.test(code) || !checkCode(code, row.code_hash)) {
    const attempts = row.attempts + 1;
    db.prepare('UPDATE login_codes SET attempts = ? WHERE id = ?').run(attempts, row.id);
    const left = CODE_TRIES - attempts;
    const error = left > 0 ? `That code is not right. ${left} ${left === 1 ? 'try' : 'tries'} left.` : 'That code is not right. Send a new code.';
    return res.status(400).json({ error });
  }

  db.prepare('UPDATE login_codes SET used_at = ? WHERE id = ?').run(iso(at), row.id);

  // Checked again: the invitation may have been cancelled, or access removed, since the code was sent.
  const access = findAccess(address, at);
  if (!access) {
    return res.status(403).json({ error: NO_ACCESS });
  }

  const token = makeToken();
  const user = db.transaction(() => {
    let userId = access.user?.id;

    // The first sign-in with an invitation: the invitation is accepted and the member is
    // created, with the name from the invitation and Caro's four occasions to start from.
    // They start onboarding at step 1.
    if (!userId) {
      userId = db
        .prepare('INSERT INTO users (email, name, created_at) VALUES (?, ?, ?)')
        .run(address, access.invitation.name, iso(at)).lastInsertRowid;
      db.prepare(`UPDATE invitations SET status = 'accepted' WHERE id = ?`).run(access.invitation.id);
      proposeFor(userId);
    }

    // Only the token's hash is stored. The token itself goes to the app, once.
    db.prepare('INSERT INTO sessions (user_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(
      userId,
      hashToken(token),
      iso(at),
      iso(at)
    );
    db.prepare('UPDATE users SET last_active_at = ? WHERE id = ?').run(iso(at), userId);

    return db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  })();

  res.json({ token, member: memberJSON(user) });
});

router.post('/sign-out', requireMember, (req, res) => {
  db.prepare('DELETE FROM sessions WHERE id = ?').run(req.sessionId);
  res.json({ ok: true });
});

module.exports = router;
