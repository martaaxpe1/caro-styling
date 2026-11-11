// The signed-in member and their set-up (PRD sections 5 and 8).
//
// GET  /me                      who is signed in, and which screen to show (onboarding or the app)
// GET  /me/setup                everything onboarding steps 1 to 5 and Settings show
// PUT  /me/name                 step 1
// PUT  /me/place                step 2: city and formats (with the new year, when the city changes in Settings)
// GET  /me/year                 step 3: the city's typical weather and the proposed years
// PUT  /me/year                 step 3: the year the member confirmed
// PUT  /me/sections             step 4: the store sections (the stores themselves are in stores.js)
// POST /me/onboarding/skip-stores   step 4: Skip for now
// POST /me/onboarding/finish        step 5: set-up done, on to building the wardrobe
//
// Every route runs behind requireMember and uses only req.member.id. Each save in onboarding
// moves the member on one step, so the app can resume where they stopped. Every save answers
// with the whole set-up, so the app always shows what the server holds.

const express = require('express');
const db = require('../db');
const { now, iso } = require('../lib/today');
const { memberJSON, advanceOnboarding } = require('../lib/members');
const { requireMember } = require('../middleware/signed-in');
const places = require('../lib/places');
const weather = require('../lib/weather');
const { proposeYear, checkSeasons } = require('../lib/year');
const setup = require('../lib/setup');

const router = express.Router();
router.use(requireMember);

router.get('/', (req, res) => {
  res.json({ member: memberJSON(req.member) });
});

router.get('/setup', (req, res) => {
  res.json(setup.setupJSON(req.member.id));
});

// Step 1: what should we call you?
router.put('/name', (req, res) => {
  const name = String(req.body?.name ?? '').trim();
  if (!name) return res.status(400).json({ error: 'Add your name.' });
  if (name.length > 40) return res.status(400).json({ error: 'Keep your name to 40 letters.' });

  db.prepare('UPDATE users SET name = ? WHERE id = ?').run(name, req.member.id);
  advanceOnboarding(req.member.id, 2);
  res.json(setup.setupJSON(req.member.id));
});

// Step 2: where you live, and the formats the member confirmed.
//   { cityId, currency, dateOrder, sizeSystem, seasons? }
// A new city needs a new year. In Settings, the app sends both together, after the member
// confirmed the year, so nothing changes until then. In onboarding, a new city takes the
// member back to step 3.
router.put('/place', async (req, res, next) => {
  try {
    const body = req.body || {};
    const currency = String(body.currency ?? '').toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency)) return res.status(400).json({ error: 'Choose a currency.' });
    if (!setup.DATE_ORDERS.includes(body.dateOrder)) return res.status(400).json({ error: 'Choose how dates look.' });
    if (!setup.SIZE_SYSTEMS.includes(body.sizeSystem)) return res.status(400).json({ error: 'Choose a size system.' });

    const city = await places.cityById(body.cityId);
    if (!city) return res.status(404).json({ error: 'Caro could not find this city. Search for it again.' });

    let seasons = null;
    if (body.seasons !== undefined) {
      const checked = checkSeasons(body.seasons);
      if (checked.error) return res.status(400).json({ error: checked.error });
      seasons = checked.seasons;
    }

    const member = req.member;
    const formats = { currency, dateOrder: body.dateOrder, sizeSystem: body.sizeSystem };
    const newCity = member.city_id !== city.id;
    const hadYear = setup.yearConfirmed(member);

    if (newCity && hadYear && !seasons && member.status === 'active') {
      return res.status(400).json({ error: 'Confirm your year for the new city first.' });
    }

    db.transaction(() => {
      setup.savePlace(member.id, city, formats);
      if (seasons) {
        setup.saveSeasons(member.id, seasons);
        advanceOnboarding(member.id, 3);
        advanceOnboarding(member.id, 4);
      } else if (newCity && hadYear) {
        // Onboarding, back at step 2 with another city: the year must be confirmed again.
        setup.clearSeasons(member.id);
        db.prepare(`UPDATE users SET onboarding_step = 3 WHERE id = ? AND status = 'onboarding'`).run(member.id);
      } else {
        advanceOnboarding(member.id, 3);
      }
    })();

    res.json(setup.setupJSON(member.id));
  } catch (error) {
    next(error);
  }
});

// Step 3: the typical weather of the member's city (or ?cityId= for a city they are moving to
// in Settings) and the three years the rule proposes. The first time a city is asked for,
// this can take a few seconds: Claude and Open-Meteo are asked, then the answer is kept.
router.get('/year', async (req, res, next) => {
  try {
    const member = req.member;
    const city = req.query.cityId ? await places.cityById(req.query.cityId) : await places.cityForMember(member);
    if (!city) return res.status(400).json({ error: 'Choose where you live first.' });

    const months = await weather.typicalWeather(city, member.id);
    const { suggested, options } = proposeYear(months, city.latitude);
    const isMemberCity = city.id === db.prepare('SELECT city_id FROM users WHERE id = ?').pluck().get(member.id);

    res.json({
      city: places.cityJSON(city),
      months,
      suggested,
      options,
      // The year the member already confirmed for this city, to show instead of a proposal.
      saved: isMemberCity && setup.yearConfirmed(member) ? setup.seasonsFor(member.id) : null,
      today: iso(now()).slice(0, 10),
    });
  } catch (error) {
    if (error instanceof weather.WeatherError || error instanceof places.PlaceError) {
      return res.status(502).json({ error: error.message });
    }
    next(error);
  }
});

// Step 3: { seasons: [{ name, months: [5, 6, ...] }, ...] }, four, two or none.
router.put('/year', (req, res) => {
  if (!req.member.city) return res.status(400).json({ error: 'Choose where you live first.' });
  const checked = checkSeasons(req.body?.seasons);
  if (checked.error) return res.status(400).json({ error: checked.error });

  db.transaction(() => {
    setup.saveSeasons(req.member.id, checked.seasons);
    advanceOnboarding(req.member.id, 4);
  })();
  res.json(setup.setupJSON(req.member.id));
});

// Step 4: { womens, mens, unisex }, at least one. What the member shops for, not who they are.
router.put('/sections', (req, res) => {
  const body = req.body || {};
  const sections = [body.womens, body.mens, body.unisex].map((value) => value === true);
  if (!sections.some(Boolean)) {
    return res.status(400).json({ error: 'Choose at least one section.' });
  }

  db.transaction(() => {
    db.prepare('UPDATE users SET shops_womens = ?, shops_mens = ?, shops_unisex = ? WHERE id = ?').run(
      ...sections.map(Number),
      req.member.id
    );
    advanceOnboarding(req.member.id, 5);
  })();
  res.json(setup.setupJSON(req.member.id));
});

// Step 4: Skip for now. Stores and sections are only needed for the store search.
router.post('/onboarding/skip-stores', (req, res) => {
  advanceOnboarding(req.member.id, 5);
  res.json(setup.setupJSON(req.member.id));
});

// Step 5: Continue after the occasions. Set-up is done: the member becomes active at step 6.
router.post('/onboarding/finish', (req, res) => {
  advanceOnboarding(req.member.id, 6);
  res.json(setup.setupJSON(req.member.id));
});

module.exports = router;
