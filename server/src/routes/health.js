const express = require('express');

const router = express.Router();

// The app calls this to check that it can reach the server.
// Render will also use it to check that the server is up (T8).
router.get('/', (req, res) => {
  res.json({ ok: true });
});

module.exports = router;
