// GET /lists: the fixed lists (chapters and kinds, colours, patterns, materials, warmth,
// formality), so the app shows the same words the server checks. Signed in only.

const express = require('express');
const { requireMember } = require('../middleware/signed-in');
const { listsJSON } = require('../lib/lists');

const router = express.Router();

router.get('/', requireMember, (req, res) => {
  res.json(listsJSON());
});

module.exports = router;
