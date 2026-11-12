// The admin area (PRD section 4): members, add person, invitations, remove and restore access.
//
// Every route here runs behind requireMember and requireAdmin, so a member who calls one
// gets "Only the admin can do this", whatever the app shows. Nothing here returns photos or
// anything from a wardrobe: the admin sees people and totals only.

const express = require('express');
const db = require('../db');
const { now, iso, DAY } = require('../lib/today');
const { cleanEmail, looksLikeEmail } = require('../lib/auth');
const email = require('../lib/email');
const { KEEP_REMOVED_DAYS, statusAfterRestore } = require('../lib/members');
const { requireMember, requireAdmin } = require('../middleware/signed-in');

const router = express.Router();
router.use(requireMember, requireAdmin);

const INVITATION_DAYS = 14;

function later(date, days) {
  return new Date(date.getTime() + days * DAY);
}

// Sends the invitation email. If Resend fails, the invitation is still saved, so the
// admin is told to resend it. Returns false when it already answered with that error.
async function sendInvitation(invitation, invitedBy, res) {
  try {
    await email.sendInvitation(invitation, invitedBy);
    return true;
  } catch (err) {
    if (!(err instanceof email.EmailError)) throw err;
    res.status(502).json({ error: 'The invitation is saved, but the email did not go out. Resend it from Invitations.' });
    return false;
  }
}

function memberRow(user) {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    status: user.status,
    city: user.city,
    country: user.country,
    joinedAt: user.created_at,
    lastActiveAt: user.last_active_at,
    aiActionsThisMonth: user.ai_actions ?? 0,
    removedAt: user.removed_at,
    deletedOn: user.removed_at ? iso(later(new Date(user.removed_at), KEEP_REMOVED_DAYS)) : null,
  };
}

function invitationRow(invitation) {
  return {
    id: invitation.id,
    name: invitation.name,
    email: invitation.email,
    sentAt: invitation.sent_at,
    expiresAt: invitation.expires_at,
  };
}

// The id in the address, like 12 in /admin/members/12/remove.
function idFrom(req) {
  const id = Number(req.params.id);
  return Number.isInteger(id) ? id : null;
}

function findMember(req) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(idFrom(req));
}

// Pending, even if its 14 days just ran out and the clean-up has not marked it yet.
function findPendingInvitation(req) {
  return db.prepare(`SELECT * FROM invitations WHERE id = ? AND status = 'pending'`).get(idFrom(req));
}

// GET /admin: everything the admin screen shows, in one go.
router.get('/', (req, res) => {
  const at = now();
  const monthStart = iso(new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), 1)));

  // The admin first, then members in the order they joined.
  const members = db
    .prepare(
      `SELECT users.*,
         (SELECT COUNT(*) FROM ai_usage WHERE ai_usage.user_id = users.id AND ai_usage.created_at >= ?) AS ai_actions
       FROM users
       ORDER BY role = 'admin' DESC, created_at`
    )
    .all(monthStart)
    .map(memberRow);

  // Only invitations still waiting: accepted ones are members, cancelled and expired ones are gone.
  const invitations = db
    .prepare(`SELECT * FROM invitations WHERE status = 'pending' AND expires_at > ? ORDER BY sent_at DESC`)
    .all(iso(at))
    .map(invitationRow);

  res.json({ members, invitations });
});

// Add person: a name and an email, then the invitation goes out. Open for 14 days.
router.post('/invitations', async (req, res) => {
  const name = String(req.body?.name ?? '').trim();
  const address = cleanEmail(req.body?.email);

  if (!name) {
    return res.status(400).json({ error: 'Add their name.' });
  }
  if (!looksLikeEmail(address)) {
    return res.status(400).json({ error: 'This email does not look right.' });
  }

  const user = db.prepare('SELECT status FROM users WHERE email = ?').get(address);
  if (user?.status === 'removed') {
    return res.status(409).json({ error: 'Access for this email was removed. Restore it under Members.' });
  }
  if (user) {
    return res.status(409).json({ error: 'This email is already a member.' });
  }

  const at = now();
  const invitation = db.transaction(() => {
    // An invitation whose 14 days ran out but that the clean-up has not marked yet.
    db.prepare(`UPDATE invitations SET status = 'expired' WHERE email = ? AND status = 'pending' AND expires_at <= ?`).run(
      address,
      iso(at)
    );

    const waiting = db.prepare(`SELECT 1 FROM invitations WHERE email = ? AND status = 'pending'`).get(address);
    if (waiting) return null;

    const { lastInsertRowid } = db
      .prepare(
        `INSERT INTO invitations (name, email, invited_by, status, sent_at, expires_at)
         VALUES (?, ?, ?, 'pending', ?, ?)`
      )
      .run(name, address, req.member.id, iso(at), iso(later(at, INVITATION_DAYS)));
    return db.prepare('SELECT * FROM invitations WHERE id = ?').get(lastInsertRowid);
  })();

  if (!invitation) {
    return res.status(409).json({ error: 'This email already has an invitation waiting. Resend it instead.' });
  }

  if (!(await sendInvitation({ name, email: address, expiresAt: invitation.expires_at }, req.member.name, res))) return;
  res.status(201).json({ invitation: invitationRow(invitation) });
});

// Resend: the invitation goes out again and is open for another 14 days from today.
router.post('/invitations/:id/resend', async (req, res) => {
  const invitation = findPendingInvitation(req);
  if (!invitation) {
    return res.status(404).json({ error: 'This invitation is no longer waiting.' });
  }

  const at = now();
  db.prepare('UPDATE invitations SET sent_at = ?, expires_at = ? WHERE id = ?').run(
    iso(at),
    iso(later(at, INVITATION_DAYS)),
    invitation.id
  );
  const updated = db.prepare('SELECT * FROM invitations WHERE id = ?').get(invitation.id);

  if (!(await sendInvitation({ name: updated.name, email: updated.email, expiresAt: updated.expires_at }, req.member.name, res))) return;
  res.json({ invitation: invitationRow(updated) });
});

// Cancel: the email can no longer sign in with this invitation.
router.post('/invitations/:id/cancel', (req, res) => {
  const invitation = findPendingInvitation(req);
  if (!invitation) {
    return res.status(404).json({ error: 'This invitation is no longer waiting.' });
  }

  db.prepare(`UPDATE invitations SET status = 'cancelled' WHERE id = ?`).run(invitation.id);
  res.json({ ok: true });
});

// Remove access: the person is signed out at once and can no longer sign in.
// Their data is kept for 30 days in case it was a mistake, then the clean-up deletes it.
router.post('/members/:id/remove', (req, res) => {
  const user = findMember(req);
  if (!user) {
    return res.status(404).json({ error: 'This member no longer exists.' });
  }
  if (user.role === 'admin') {
    return res.status(400).json({ error: "The admin's access cannot be removed." });
  }

  if (user.status !== 'removed') {
    db.transaction(() => {
      db.prepare(`UPDATE users SET status = 'removed', removed_at = ? WHERE id = ?`).run(iso(now()), user.id);
      // Ending every session signs them out on all their devices.
      db.prepare('DELETE FROM sessions WHERE user_id = ?').run(user.id);
    })();
  }

  res.json({ member: memberRow(findMember(req)) });
});

// Restore access, within 30 days of removing it. Everything is as they left it.
router.post('/members/:id/restore', (req, res) => {
  const user = findMember(req);
  if (!user) {
    return res.status(404).json({ error: 'This member no longer exists.' });
  }

  if (user.status === 'removed') {
    const deletedOn = later(new Date(user.removed_at), KEEP_REMOVED_DAYS);
    if (now() >= deletedOn) {
      return res.status(409).json({ error: 'More than 30 days have passed, so this data is being deleted.' });
    }
    db.prepare('UPDATE users SET status = ?, removed_at = NULL WHERE id = ?').run(statusAfterRestore(user), user.id);
  }

  res.json({ member: memberRow(findMember(req)) });
});

module.exports = router;
