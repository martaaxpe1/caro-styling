// Sign-in codes and session tokens, and their hashes.
//
// A hash is a one-way fingerprint: the same input always gives the same fingerprint,
// but the fingerprint cannot be turned back into the input. The database keeps only
// fingerprints, so even someone with a copy of it cannot sign in as anyone.
//
// Everything here uses Node's own crypto module, so no extra package is needed.

const crypto = require('crypto');

// A 6-digit code, like 042917. randomInt is the secure kind of random, unlike Math.random.
function makeCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

// A code has only a million possible values, so it gets a deliberately slow hash (scrypt)
// with a random salt. Kept in the database as "salt:hash".
function hashCode(code) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(code, salt, 32).toString('hex');
  return `${salt}:${hash}`;
}

// True when the code typed matches the stored hash.
function checkCode(code, stored) {
  const [salt, hash] = stored.split(':');
  const expected = Buffer.from(hash, 'hex');
  const actual = crypto.scryptSync(code, salt, 32);
  // Compares in constant time, so how long it takes gives nothing away.
  return crypto.timingSafeEqual(expected, actual);
}

// A session token: 32 random bytes, written as about 43 letters and digits.
// Far too long to guess, so the app can keep using it until the member signs out.
function makeToken() {
  return crypto.randomBytes(32).toString('base64url');
}

// A token is long and random, so a fast hash is enough. The same token always gives
// the same hash, which is how the server finds its session.
function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// Emails are kept in lower case with no spaces around them, so Sara@Example.com and
// sara@example.com are the same person.
function cleanEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

// A light check: something, an @, something, a dot, something. The real check is the code.
function looksLikeEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

module.exports = { makeCode, hashCode, checkCode, makeToken, hashToken, cleanEmail, looksLikeEmail };
