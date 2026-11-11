// A member's stores (onboarding step 4 and Settings, PRD sections 5 and 9).
//
// POST   /me/stores/find   { name }   Claude finds the store's site for the member's country
// POST   /me/stores        { name, domain, countryUrl, sellsOnline }   Add, after the member confirms
// PUT    /me/stores/:id    { domain, countryUrl, sellsOnline }   A new site, after the member moved
// DELETE /me/stores/:id    Remove
//
// Finding and adding are two steps, so the member sees the site before it is added.
// Every query has user_id = the signed-in member: nobody reaches another member's stores.

const express = require('express');
const db = require('../db');
const { now, iso } = require('../lib/today');
const { requireMember } = require('../middleware/signed-in');
const { ClaudeError, recordAiAction } = require('../lib/claude');
const stores = require('../lib/stores');
const setup = require('../lib/setup');

const router = express.Router();
router.use(requireMember);

function findStore(req) {
  const id = Number(req.params.id);
  return Number.isInteger(id) ? db.prepare('SELECT * FROM stores WHERE id = ? AND user_id = ?').get(id, req.member.id) : null;
}

// The website part of a request, checked: a domain like cos.com, and an https shop address
// on that domain when the store sells online in the member's country.
function websiteFrom(body) {
  const domain = stores.domainOf(String(body?.domain ?? ''));
  if (!domain) return { error: 'This store has no website Caro can use.' };
  const sellsOnline = body?.sellsOnline === true;
  if (!sellsOnline) return { domain, countryUrl: null, sellsOnline };
  const countryUrl = stores.shopUrl(String(body?.countryUrl ?? ''));
  const host = countryUrl && stores.domainOf(countryUrl);
  if (!host || !(host === domain || host.endsWith(`.${domain}`))) {
    return { error: 'This shop address does not look right.' };
  }
  return { domain, countryUrl, sellsOnline };
}

router.post('/find', async (req, res, next) => {
  const name = String(req.body?.name ?? '').trim();
  if (!name) return res.status(400).json({ error: 'Type the name of a store.' });
  if (name.length > 60) return res.status(400).json({ error: 'Keep the name to 60 letters.' });
  if (!req.member.country) return res.status(400).json({ error: 'Choose where you live first.' });

  try {
    const store = await stores.findWebsite(name, req.member.country, req.member.currency);
    recordAiAction(req.member.id, 'store website');
    res.json({ store });
  } catch (error) {
    if (error instanceof ClaudeError) {
      console.error(`Store website for "${name}" failed: ${error.message}`);
      return res.status(502).json({ error: 'Caro could not look this store up just now. Try again.' });
    }
    next(error);
  }
});

router.post('/', (req, res) => {
  const name = String(req.body?.name ?? '').trim().slice(0, 60);
  if (!name) return res.status(400).json({ error: 'Type the name of a store.' });
  if (!req.member.country) return res.status(400).json({ error: 'Choose where you live first.' });
  const website = websiteFrom(req.body);
  if (website.error) return res.status(400).json({ error: website.error });

  const already = db.prepare('SELECT name FROM stores WHERE user_id = ? AND domain = ?').get(req.member.id, website.domain);
  if (already) return res.status(409).json({ error: `${already.name} is already in your stores.` });

  const position = db.prepare('SELECT COALESCE(MAX(position), 0) + 1 FROM stores WHERE user_id = ?').pluck().get(req.member.id);
  db.prepare(
    `INSERT INTO stores (user_id, name, domain, country_url, sells_online, country, position, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(req.member.id, name, website.domain, website.countryUrl, website.sellsOnline ? 1 : 0, req.member.country, position, iso(now()));

  res.status(201).json(setup.setupJSON(req.member.id));
});

router.put('/:id', (req, res) => {
  const store = findStore(req);
  if (!store) return res.status(404).json({ error: 'This store is no longer in your list.' });
  const website = websiteFrom(req.body);
  if (website.error) return res.status(400).json({ error: website.error });

  db.prepare('UPDATE stores SET domain = ?, country_url = ?, sells_online = ?, country = ? WHERE id = ? AND user_id = ?').run(
    website.domain,
    website.countryUrl,
    website.sellsOnline ? 1 : 0,
    req.member.country,
    store.id,
    req.member.id
  );
  res.json(setup.setupJSON(req.member.id));
});

router.delete('/:id', (req, res) => {
  const store = findStore(req);
  if (!store) return res.status(404).json({ error: 'This store is no longer in your list.' });
  db.prepare('DELETE FROM stores WHERE id = ? AND user_id = ?').run(store.id, req.member.id);
  res.json(setup.setupJSON(req.member.id));
});

module.exports = router;
