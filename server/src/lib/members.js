// Small rules about members, shared by the routes and the clean-up job.

const db = require('../db');
const { hasPieces } = require('./wardrobe');

// A removed member's data is kept this long, so the admin can restore access, then deleted.
const KEEP_REMOVED_DAYS = 30;

// What the app is told about the signed-in member. Never the photos or the wardrobe.
// unlocked: Looks and Get the look are open. wardrobeStarted: the member has added pieces
// (or is unlocked), so the app opens on the edit instead of step 6.
function memberJSON(user) {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    status: user.status,
    onboardingStep: user.onboarding_step,
    country: user.country,
    unlocked: Boolean(user.unlocked_at),
    wardrobeStarted: Boolean(user.unlocked_at) || hasPieces(user.id),
  };
}

// The status a member gets back when the admin restores access: onboarding if they had
// not finished set-up (steps 1 to 5), active otherwise. Finishing step 5 moves a member to
// active at step 6 (advanceOnboarding below), so the two stay in step.
function statusAfterRestore(user) {
  return user.onboarding_step < 6 ? 'onboarding' : 'active';
}

// Onboarding moves on one step at a time: saving step N moves a member from step N to N + 1.
// A member who is further on stays there, and one who is not at step N yet does not move,
// so no step can be skipped by calling the server directly.
// Reaching step 6 means set-up is done: the member becomes active and builds their wardrobe.
// Members who are already active (changing things in Settings) never move.
function advanceOnboarding(userId, toStep) {
  db.prepare(
    `UPDATE users SET onboarding_step = ?, status = CASE WHEN ? >= 6 THEN 'active' ELSE status END
     WHERE id = ? AND status = 'onboarding' AND onboarding_step = ?`
  ).run(toStep, toStep, userId, toStep - 1);
}

// Deletes a member from the database: every table holding their data has user_id with
// ON DELETE CASCADE, so deleting the member deletes all of it (pieces, looks, seasons, stores,
// sessions, AI usage). Their invitation and sign-in codes are kept by email, so they go too.
// The photo files are removed by the caller, once this has run (removeMemberPhotos).
function deleteMember(user) {
  db.transaction(() => {
    db.prepare('DELETE FROM users WHERE id = ?').run(user.id);
    db.prepare('DELETE FROM invitations WHERE email = ?').run(user.email);
    db.prepare('DELETE FROM login_codes WHERE email = ?').run(user.email);
  })();
}

module.exports = { KEEP_REMOVED_DAYS, memberJSON, statusAfterRestore, advanceOnboarding, deleteMember };
