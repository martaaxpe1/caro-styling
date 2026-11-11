// GET /me: the signed-in member. The app asks this when it opens, to know who is signed in
// and which screen to show (onboarding or the app). T4 adds changing your own details here.

const express = require('express');
const { memberJSON } = require('../lib/members');
const { requireMember } = require('../middleware/signed-in');

const router = express.Router();

router.get('/', requireMember, (req, res) => {
  res.json({ member: memberJSON(req.member) });
});

module.exports = router;
