// Middleware: Looks and Get the look are open only once the wardrobe is (PRD sections 5 and 8).
//
// Runs after requireMember. The unlock rule is checked on the server: unlocked_at is set the
// moment a member reaches it (src/lib/wardrobe.js) and never cleared, so once open, it stays open.

function requireUnlocked(req, res, next) {
  if (!req.member?.unlocked_at) {
    return res.status(403).json({ error: 'Looks open at 20 pieces, with a top, a bottom or dress, and shoes.' });
  }
  next();
}

module.exports = { requireUnlocked };
