// Find it (PRD sections 7, 8 and 10, screen S11): search the member's stores for one key piece.
//
// The way the T1 spike recommended (docs/SPIKE.md test 4, server/spike/4-stores.js), with
// Marta's choice of one search over all her stores at once:
// 1. Haiku with web search, limited to the websites of the member's stores, searched from the
//    member's country. The whole website, not only the country page: a search limited to the
//    country page found nothing when the search engine did not know that page.
// 2. Only products in the member's currency, from the sections they shop in (women's, men's,
//    unisex). Never children's.
// 3. Haiku's web fetch opens each product page, to get its image and to drop dead links.
// The server then checks every answer itself: a link on one of the member's stores, their
// currency, a price, an https image. Up to five. "Nothing found" is a valid answer.
//
// Claude only looks up what the stores list for the piece the member asked about. It never
// recommends, never suggests other pieces, never comments on style.
//
// Every function takes the member's own id and touches only their rows.

const db = require('../db');
const { ask, ClaudeError, recordAiAction } = require('./claude');
const allowance = require('./allowance');
const { domainOf } = require('./stores');
const { now, iso } = require('./today');

const MAX_RESULTS = 5;

const countryNames = new Intl.DisplayNames(['en'], { type: 'region' });
// Countries said with "the": the Netherlands, the United States.
const WITH_THE = new Set(['NL', 'US', 'GB', 'AE', 'CZ', 'DO', 'PH', 'BS', 'GM', 'MV', 'KY', 'VA']);
function placeName(country) {
  return `${WITH_THE.has(country) ? 'the ' : ''}${countryNames.of(country)}`;
}

const SYSTEM = `You search a person's own stores for one piece they asked about, and report what the stores list: names, prices, links and images.
You never recommend, never suggest other pieces, and never comment on style.`;

const SCHEMA = {
  type: 'object',
  properties: {
    products: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          price: { type: 'number' },
          currency: { type: 'string' },
          url: { type: 'string' },
          image_url: { type: 'string' },
        },
        required: ['name', 'price', 'currency', 'url', 'image_url'],
        additionalProperties: false,
      },
    },
  },
  required: ['products'],
  additionalProperties: false,
};

const SECTION_NAMES = [
  ['shops_womens', "women's"],
  ['shops_mens', "men's"],
  ['shops_unisex', 'unisex'],
];

function sectionsOf(member) {
  return SECTION_NAMES.filter(([column]) => member[column] === 1).map(([, name]) => name);
}

function listText(names) {
  return names.length > 1 ? `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}` : names[0];
}

// The member's stores, split: the ones Caro may search, and the ones it may not, with why.
function storesFor(member) {
  const place = placeName(member.country);
  const all = db.prepare('SELECT * FROM stores WHERE user_id = ? ORDER BY position').all(member.id);
  const searched = [];
  const skipped = [];
  for (const store of all) {
    if (store.country !== member.country) {
      skipped.push({ store: store.name, reason: `${store.name} was not checked for ${place} yet, so it was not searched.` });
    } else if (!store.sells_online || !store.country_url) {
      skipped.push({ store: store.name, reason: `${store.name} has no online shop in ${place}, so it was not searched.` });
    } else {
      searched.push(store);
    }
  }
  return { searched, skipped };
}

function prompt(member, stores, piece) {
  const place = placeName(member.country);
  const shops = stores.map((s) => `- ${s.name}: ${s.domain} (its shop for ${place}: ${s.country_url})`).join('\n');
  return `Search these stores' online shops for ${place} for one piece: "${piece}".

The stores:
${shops}

Search each store's whole website. Return up to ${MAX_RESULTS} products listed in these shops that match the description, closest first. Only products sold in the shop for ${place}, with prices in ${member.currency}. Only products from the shops' ${listText(sectionsOf(member))} sections: leave out every other section, including children's.
Open each product page you return with web fetch, to check that it still works and to find its main product image. Leave out any product whose page does not open.
For each product: the name as the shop writes it, the price as a number, the three-letter currency code, the address of the product page, and the address of its main image (empty if you could not find one).
If nothing matches, return an empty list. That is a valid answer.`;
}

// Web search and web fetch, limited to the stores. The newest tool versions first; if the
// model does not take them, the basic ones.
const TOOL_VERSIONS = [
  ['web_search_20260209', 'web_fetch_20260209'],
  ['web_search_20250305', 'web_fetch_20250910'],
];

function toolsFor(member, stores, [search, fetch]) {
  const domains = [...new Set(stores.map((s) => s.domain))];
  return [
    { type: search, name: 'web_search', max_uses: 5, allowed_domains: domains, user_location: { type: 'approximate', country: member.country } },
    { type: fetch, name: 'web_fetch', max_uses: 8, allowed_domains: domains },
  ];
}

// The parts that ask another service. The tests replace them, so they cost nothing.
const remote = {
  async claude(member, stores, piece) {
    let lastError;
    for (const versions of TOOL_VERSIONS) {
      try {
        return await ask({ model: 'haiku', system: SYSTEM, prompt: prompt(member, stores, piece), schema: SCHEMA, tools: toolsFor(member, stores, versions) });
      } catch (error) {
        lastError = error;
        if (!(error instanceof ClaudeError) || !/error 400/.test(error.message)) throw error;
      }
    }
    throw lastError;
  },

  // Without AI: the product page's preview image (og:image), when Claude found none.
  async previewImage(url) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(8000),
        headers: { 'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1' },
      });
      if (!response.ok) return null;
      const html = (await response.text()).slice(0, 500000);
      const match =
        html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
        html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
      return match ? httpsUrl(match[1].replace(/&amp;/g, '&')) : null;
    } catch {
      return null;
    }
  },
};

function httpsUrl(address) {
  try {
    const url = new URL(String(address ?? '').trim());
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

// The store a link belongs to: its host is the store's domain, or a part of it (www.cos.com).
function storeForUrl(url, stores) {
  const host = domainOf(url);
  if (!host) return null;
  return stores.find((s) => host === s.domain || host.endsWith(`.${s.domain}`)) ?? null;
}

// Claude's answer, checked by the server. Products on another site, in another currency, or
// without a price are left out. Each link once.
function checked(answer, member, stores) {
  const products = [];
  const seen = new Set();
  for (const item of Array.isArray(answer?.products) ? answer.products : []) {
    const url = httpsUrl(item?.url);
    const store = url && storeForUrl(url, stores);
    if (!store || seen.has(url)) continue;
    if (String(item?.currency ?? '').trim().toUpperCase() !== member.currency) continue;
    const price = Number(item?.price);
    if (!Number.isFinite(price) || price <= 0 || price > 100000) continue;
    const name = String(item?.name ?? '').trim().slice(0, 120);
    if (!name) continue;
    seen.add(url);
    products.push({ store, name, priceCents: Math.round(price * 100), currency: member.currency, url, imageUrl: httpsUrl(item?.image_url) });
    if (products.length === MAX_RESULTS) break;
  }
  return products;
}

// The words Claude searches for: the piece as Caro described it, with its shape.
function pieceText(row) {
  return [row.description, row.shape].filter(Boolean).join(', ');
}

function findToFind(userId, id) {
  const toFindId = Number(id);
  if (!Number.isInteger(toFindId)) return null;
  return db.prepare('SELECT * FROM to_find WHERE id = ? AND user_id = ?').get(toFindId, userId) ?? null;
}

// Starts a search: refused (with the message to show) when the member has no store to search
// or no AI actions left. Otherwise marks it searching; the queue does the rest.
function startSearch(userId, toFind) {
  const member = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  if (toFind.status === 'bought') return { error: 'You already bought this piece.' };
  if (!member.country || !member.currency) return { error: 'Choose where you live first, in Settings.' };
  if (sectionsOf(member).length === 0) return { error: 'Choose the sections you shop in first, in Settings, under Your stores.' };
  if (storesFor(member).searched.length === 0) {
    return { error: 'None of your stores has an online shop Caro can search in your country. Add one in Settings, under Your stores.' };
  }
  if (!allowance.hasRoom(userId)) return { error: allowance.message(), status: 429 };
  db.prepare(`UPDATE to_find SET search_status = 'searching', search_message = NULL WHERE id = ? AND user_id = ?`).run(toFind.id, userId);
  return null;
}

// Runs one search (from the queue). Counts one AI action. If Claude cannot answer, the
// search is "failed" and the member can search again.
async function runSearch(toFind) {
  const userId = toFind.user_id;
  const member = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  const row = db.prepare('SELECT * FROM inspiration_pieces WHERE id = ? AND user_id = ?').get(toFind.inspiration_piece_id, userId);
  const { searched } = storesFor(member);
  try {
    if (!row || searched.length === 0) throw new ClaudeError('Nothing to search.');
    allowance.check(userId);
    recordAiAction(userId, 'store search');
    const products = checked(await remote.claude(member, searched, pieceText(row)), member, searched);
    for (const product of products) {
      if (!product.imageUrl) product.imageUrl = await remote.previewImage(product.url);
    }
    saveResults(toFind, products);
  } catch (error) {
    console.error(`Store search for To find ${toFind.id} failed: ${error.message}`);
    const message = error instanceof allowance.AllowanceError ? error.message : 'Caro could not search your stores just now. Try again.';
    db.prepare(`UPDATE to_find SET search_status = 'failed', search_message = ? WHERE id = ? AND search_status = 'searching'`).run(message, toFind.id);
  }
}

// Saves what was found. Products the member kept stay; the others are replaced. A product
// found again that was kept or discarded keeps that choice.
function saveResults(toFind, products) {
  db.transaction(() => {
    const still = db.prepare(`SELECT 1 FROM to_find WHERE id = ? AND search_status = 'searching'`).get(toFind.id);
    if (!still) return;
    const decided = new Map(
      db.prepare('SELECT url, decision FROM store_results WHERE to_find_id = ? AND decision IS NOT NULL').all(toFind.id).map((r) => [r.url, r.decision])
    );
    db.prepare(`DELETE FROM store_results WHERE to_find_id = ? AND (decision IS NULL OR decision = 'discarded')`).run(toFind.id);
    const add = db.prepare(
      `INSERT INTO store_results (user_id, to_find_id, store_id, name, price_cents, currency, url, image_url, found_at, decision)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const at = iso(now());
    for (const p of products) {
      const decision = decided.get(p.url) ?? null;
      if (decision === 'kept') {
        // Already there: refresh its price and date.
        db.prepare('UPDATE store_results SET price_cents = ?, image_url = COALESCE(?, image_url), found_at = ? WHERE to_find_id = ? AND url = ?').run(
          p.priceCents, p.imageUrl, at, toFind.id, p.url
        );
        continue;
      }
      add.run(toFind.user_id, toFind.id, p.store.id, p.name, p.priceCents, p.currency, p.url, p.imageUrl, at, decision);
    }
    db.prepare(`UPDATE to_find SET search_status = 'done', search_message = NULL, searched_at = ? WHERE id = ?`).run(at, toFind.id);
  })();
}

function resultJSON(row) {
  return {
    id: row.id,
    name: row.name,
    store: row.store_name,
    priceCents: row.price_cents,
    currency: row.currency,
    url: row.url,
    image: row.image_url,
    foundAt: row.found_at,
    decision: row.decision,
  };
}

function resultsOf(userId, toFindId, { withDiscarded = false } = {}) {
  return db
    .prepare(
      `SELECT store_results.*, stores.name AS store_name FROM store_results
       JOIN stores ON stores.id = store_results.store_id
       WHERE store_results.to_find_id = ? AND store_results.user_id = ? ${withDiscarded ? '' : `AND (decision IS NULL OR decision = 'kept')`}
       ORDER BY decision = 'kept' DESC, store_results.id`
    )
    .all(toFindId, userId)
    .map(resultJSON);
}

// The short state for a To find row: searching, found, nothing found, failed, not searched.
function searchSummary(userId, toFind) {
  const results = resultsOf(userId, toFind.id);
  const kept = results.filter((r) => r.decision === 'kept');
  const shown = kept[0] ?? results[0] ?? null;
  return {
    searchStatus: toFind.search_status,
    searchMessage: toFind.search_message,
    found: results.length,
    kept: kept.length,
    image: shown?.image ?? null,
  };
}

module.exports = {
  MAX_RESULTS,
  remote,
  checked,
  storesFor,
  sectionsOf,
  findToFind,
  startSearch,
  runSearch,
  resultsOf,
  searchSummary,
  pieceText,
};
