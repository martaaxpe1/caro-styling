// The emails Caro sends: sign-in codes and invitations (PRD section 13).
//
// On this Mac they are printed in the terminal instead of being sent.
// Online they go through Resend (resend.com), using its web API with Node's own fetch, so no
// extra package is needed. Two settings, kept in Render, never in Git:
// - RESEND_API_KEY: the key from Resend.
// - EMAIL_FROM: the sender, on a domain verified in Resend, like Caro <caro@example.com>.
//
// Nothing here ever logs the email's text, the code in it, or the key.

const isProduction = process.env.NODE_ENV === 'production';
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Resend did not take the email. The message is safe to show in the app.
class EmailError extends Error {}

// A date like 25 Nov 2026.
function day(date) {
  const d = new Date(date);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

async function deliver({ to, subject, lines }) {
  if (!isProduction) {
    const rule = '-'.repeat(60);
    console.log(['', rule, 'Email, printed here instead of sent (development)', `To: ${to}`, `Subject: ${subject}`, '', ...lines, rule, ''].join('\n'));
    return;
  }

  const key = process.env.RESEND_API_KEY;
  const from = process.env.EMAIL_FROM;
  if (!key || !from) {
    console.error('Email not sent: RESEND_API_KEY or EMAIL_FROM is not set.');
    throw new EmailError('Caro could not send the email. Try again later.');
  }

  let response;
  try {
    response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to, subject, text: lines.join('\n') }),
      signal: AbortSignal.timeout(15000),
    });
  } catch (err) {
    console.error(`Email not sent: Resend could not be reached (${err.name}).`);
    throw new EmailError('Caro could not send the email. Try again.');
  }

  if (!response.ok) {
    // Resend's answer says what was wrong (a domain not verified, a bad key). It never holds the email's text.
    const answer = await response.text().catch(() => '');
    console.error(`Email not sent: Resend answered ${response.status} ${answer.slice(0, 300)}`);
    throw new EmailError('Caro could not send the email. Try again.');
  }
}

function sendSignInCode(to, code, minutes) {
  return deliver({
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
// Members install Caro as internal testers: Apple sends its own TestFlight invitation (T8).
function sendInvitation(invitation, invitedBy) {
  return deliver({
    to: invitation.email,
    subject: `${invitedBy} invited you to Caro`,
    lines: [
      `Hello ${invitation.name},`,
      '',
      `${invitedBy} invited you to Caro, a styling studio for the clothes you already own.`,
      '',
      '1. Apple emails you an invitation to test Caro. Install TestFlight from the App Store, then install Caro from the invitation.',
      `2. Open Caro and sign in with this email, ${invitation.email}. Caro emails you a code.`,
      '',
      `This invitation is open until ${day(invitation.expiresAt)}.`,
    ],
  });
}

module.exports = { EmailError, sendSignInCode, sendInvitation };
