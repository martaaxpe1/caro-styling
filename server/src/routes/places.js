// GET /places?q=Miami: city search for onboarding step 2, signed in only.
// The server asks Open-Meteo's city search (src/lib/places.js) and answers with up to six
// places: { cities: [{ id, name, region, country }] }.

const express = require('express');
const { requireMember } = require('../middleware/signed-in');
const places = require('../lib/places');

const router = express.Router();

router.get('/', requireMember, async (req, res, next) => {
  try {
    res.json({ cities: await places.searchCities(req.query.q) });
  } catch (error) {
    if (error instanceof places.PlaceError) {
      console.error(`City search failed: ${error.message}`);
      return res.status(502).json({ error: 'City search is not answering just now. Try again.' });
    }
    next(error);
  }
});

module.exports = router;
