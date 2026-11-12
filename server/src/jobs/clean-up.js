// The daily clean-up (PRD sections 4 and 8). A scheduled job: the server runs it by itself,
// once when it starts and then every 24 hours. `npm run clean-up` runs it by hand.
//
// 1. Invitations past their 14 days are marked expired.
// 2. Members removed more than 30 days ago are deleted, with everything they had, photos included.
// 3. Sign-in codes older than a day are deleted. They only work for 15 minutes.

const db = require('../db');
const { now, iso, DAY } = require('../lib/today');
const { KEEP_REMOVED_DAYS, deleteMember } = require('../lib/members');
const { removeMemberPhotos } = require('../lib/photos');

// `at` is the moment to clean up as of. Normally now; the tests pass a date 31 days on.
function cleanUp(at = now()) {
  const result = db.transaction(() => {
    const invitationsExpired = db
      .prepare(`UPDATE invitations SET status = 'expired' WHERE status = 'pending' AND expires_at <= ?`)
      .run(iso(at)).changes;

    const cutoff = iso(new Date(at.getTime() - KEEP_REMOVED_DAYS * DAY));
    const removed = db.prepare(`SELECT id, email FROM users WHERE status = 'removed' AND removed_at <= ?`).all(cutoff);

    for (const user of removed) {
      // Everything they had, with their invitation and codes (lib/members.js).
      deleteMember(user);
    }

    const codesDeleted = db
      .prepare('DELETE FROM login_codes WHERE created_at <= ?')
      .run(iso(new Date(at.getTime() - DAY))).changes;

    return { invitationsExpired, removed, codesDeleted };
  })();

  // Their photo files, once the database no longer points at them.
  for (const user of result.removed) removeMemberPhotos(user.id);

  return {
    invitationsExpired: result.invitationsExpired,
    membersDeleted: result.removed.length,
    codesDeleted: result.codesDeleted,
  };
}

// One line for the terminal, like "Clean-up: 1 invitation expired, 0 members deleted, 3 old codes deleted."
function describe({ invitationsExpired, membersDeleted, codesDeleted }) {
  const count = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  return (
    'Clean-up: ' +
    [
      count(invitationsExpired, 'invitation expired', 'invitations expired'),
      count(membersDeleted, 'removed member deleted', 'removed members deleted'),
      count(codesDeleted, 'old code deleted', 'old codes deleted'),
    ].join(', ') +
    '.'
  );
}

function runAndLog() {
  try {
    console.log(describe(cleanUp()));
  } catch (err) {
    console.error('Clean-up failed:', err);
  }
}

function startDailyCleanUp() {
  runAndLog();
  setInterval(runAndLog, DAY);
}

module.exports = { cleanUp, describe, startDailyCleanUp };
