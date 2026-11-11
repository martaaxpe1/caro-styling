// The emails Caro sends: sign-in codes and invitations (PRD section 13).
//
// In development they are printed in the terminal instead of being sent.
// Online, they go through Resend from T8. Until then nothing is sent online, and a
// sign-in code is never printed there.

const isProduction = process.env.NODE_ENV === 'production';
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// A date like 25 Nov 2026.
function day(date) {
  const d = new Date(date);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

function deliver({ to, subject, lines }) {
  if (isProduction) {
    // T8 sends it with Resend. Never print it here: it can hold a sign-in code.
    throw new Error('Emails are not set up online yet. Resend comes in T8.');
  }

  const rule = '-'.repeat(60);
  console.log(['', `${rule}`, 'Email, printed here instead of sent (development)', `To: ${to}`, `Subject: ${subject}`, '', ...lines, rule, ''].join('\n'));
}

function sendSignInCode(to, code, minutes) {
  deliver({
    to,
    subject: 'Your Caro code',
    lines: [
      `Your code to sign in to Caro is ${code}.`,
      '',
      `It works for ${minutes} minutes. If you did not ask for it, you can ignore this email.`,
    ],
  });
}

// invitation: { name, email, expiresAt }. invitedBy: the admin's name.
function sendInvitation(invitation, invitedBy) {
  deliver({
    to: invitation.email,
    subject: `${invitedBy} invited you to Caro`,
    lines: [
      `Hello ${invitation.name},`,
      '',
      `${invitedBy} invited you to Caro, a styling studio for the clothes you already own.`,
      '',
      '1. Install Caro with TestFlight: the link is added in T8.',
      `2. Open Caro and sign in with this email, ${invitation.email}. Caro emails you a code.`,
      '',
      `This invitation is open until ${day(invitation.expiresAt)}.`,
    ],
  });
}

module.exports = { sendSignInCode, sendInvitation };
