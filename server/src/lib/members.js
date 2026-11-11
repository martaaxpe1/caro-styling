// Small rules about members, shared by the routes and the clean-up job.

// A removed member's data is kept this long, so the admin can restore access, then deleted.
const KEEP_REMOVED_DAYS = 30;

// What the app is told about the signed-in member. Never the photos or the wardrobe.
function memberJSON(user) {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    status: user.status,
    onboardingStep: user.onboarding_step,
    country: user.country,
  };
}

// The status a member gets back when the admin restores access: onboarding if they had
// not finished set-up (steps 1 to 5), active otherwise. T4 moves a member to active at step 6,
// so keep this in step with it.
function statusAfterRestore(user) {
  return user.onboarding_step < 6 ? 'onboarding' : 'active';
}

module.exports = { KEEP_REMOVED_DAYS, memberJSON, statusAfterRestore };
