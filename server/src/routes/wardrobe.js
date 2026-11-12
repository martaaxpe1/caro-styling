// GET /me/wardrobe: what the edit shows while the wardrobe is being built (screen 08) and after:
// progress towards the unlock, pieces still being read or waiting for review, and each chapter
// with its count and its two newest cut-outs. Signed in, the member's own pieces only.

const express = require('express');
const { requireMember } = require('../middleware/signed-in');
const { wardrobeJSON } = require('../lib/wardrobe');

const router = express.Router();

router.get('/', requireMember, (req, res) => {
  res.json(wardrobeJSON(req.member.id));
});

module.exports = router;
