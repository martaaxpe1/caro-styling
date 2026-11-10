// npm run spike:stores -- --piece "black leather loafers"
// Test 4: stores.
//   (a) websites: find each store's online shop for the Netherlands and the US,
//       or say there is none there. Web search is open to the whole web.
//   (b) search: look for one piece in one store per country, with web search limited
//       to that store's website. Up to five products. Then, without AI, try to read each
//       product page's preview image.
//
// Options:
//   --part websites      only (a); --part search only (b). Default: both.
//   --model opus,sonnet  only these models (default: all three; Haiku is skipped if it cannot search)
//   --stores "COS,Arket" only these stores for (a) (default: Marta's seven)
//   --country NL         only one country (default: NL and US)
//   --piece "..."        the piece to search for in (b)
//   --search-store COS   the store to search in (b) (default COS)

const { Anthropic, ask, pickModels, describeError, MODELS } = require('./lib/claude');
const { saveJson, loadJson, readOptions, dollars } = require('./lib/output');

const STORES = ['Arket', 'COS', 'Uniqlo', 'Zara', 'Ganni', 'Bimba y Lola', 'Samsøe Samsøe'];

const COUNTRIES = {
  NL: { name: 'the Netherlands', currency: 'EUR', location: { type: 'approximate', country: 'NL', city: 'Amsterdam' } },
  US: { name: 'the United States', currency: 'USD', location: { type: 'approximate', country: 'US', city: 'Miami', region: 'Florida' } },
};

const WEBSITE_SYSTEM = `You help a person set up the list of stores they shop at. You look up facts about stores on the web.
You never recommend stores or products.`;

const SEARCH_SYSTEM = `You search one store's website for one piece a person asked about, and report what the store lists: names, prices and links.
You never recommend, never suggest other pieces, and never comment on style.`;

const WEBSITE_SCHEMA = {
  type: 'object',
  properties: {
    found: { type: 'boolean' },
    official_name: { type: 'string' },
    website: { type: 'string' },
    sells_online: { type: 'string', enum: ['yes', 'no', 'not sure'] },
    currency: { type: 'string' },
    evidence: { type: 'string' },
  },
  required: ['found', 'official_name', 'website', 'sells_online', 'currency', 'evidence'],
  additionalProperties: false,
};

const SEARCH_SCHEMA = {
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

function websitePrompt(store, country) {
  return `Find the official online shop of the store "${store}" for someone who lives in ${country.name}.

- found: whether you found the store's official website
- official_name: the store's name as it writes it
- website: the address of its online shop for ${country.name}, including the country part of the address if it has one, like https://www.example.com/nl-nl/. Empty if there is none.
- sells_online: "yes" if people in ${country.name} can buy from it online, with prices in ${country.currency}; "no" if it has no online shop for ${country.name}; "not sure" if you cannot tell
- currency: the three-letter code of the currency its shop for ${country.name} uses, or empty
- evidence: one short sentence on what you found`;
}

function searchPrompt(store, country, piece) {
  return `Search the ${store} online shop for ${country.name} for this piece: "${piece}".

Return up to five products listed in that shop that match the description, closest first. Only products from that shop, for ${country.name}.
For each product: the name as the shop writes it, the price as a number, the three-letter currency code, the address of the product page, and the address of a product image if the search results show one (empty otherwise).
If nothing matches, return an empty list. That is a valid answer.`;
}

function searchTool(version, extra) {
  return { type: version, name: 'web_search', ...extra };
}

// Asks with web search and a form to fill in. If the API does not accept that
// combination, or the model needs the older search tool, it tries the next way
// and records which one worked.
async function searchAndFill({ model, test, action, system, prompt, schema, toolOptions }) {
  const versions = model === 'haiku' ? ['web_search_20260209', 'web_search_20250305'] : ['web_search_20260209'];
  const notes = [];

  for (const version of versions) {
    const tools = [searchTool(version, toolOptions)];
    try {
      const answer = await ask({ test, action, model, effort: 'low', system, content: prompt, schema, tools, note: version });
      return { ...answer, way: `one call, ${version}`, notes };
    } catch (error) {
      if (!(error instanceof Anthropic.BadRequestError)) throw error;
      notes.push(`${version} with a form: ${error.message}`);
    }

    // Second way: search and answer in words, then a cheap call puts the answer in the form.
    try {
      const words = await ask({ test, action, model, effort: 'low', system, content: prompt, tools, note: `${version}, words` });
      const form = await ask({
        test,
        action: `${action} (form)`,
        model: 'haiku',
        effort: 'low',
        system: 'You copy facts from a text into a form. Use only what the text says.',
        content: `Put this answer into the form:\n\n${words.text}`,
        schema,
      });
      return {
        ...form,
        cost: words.cost + form.cost,
        seconds: words.seconds + form.seconds,
        usage: words.usage,
        way: `two calls, ${version}`,
        notes,
      };
    } catch (error) {
      if (!(error instanceof Anthropic.BadRequestError)) throw error;
      notes.push(`${version} without a form: ${error.message}`);
    }
  }
  throw new Error(`Web search did not work for ${MODELS[model].label}: ${notes.join(' | ')}`);
}

// Reads a product page and looks for its preview image (og:image). No AI involved.
async function previewImage(url) {
  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(10000),
      headers: {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
        'accept-language': 'en',
      },
    });
    if (!response.ok) return { ok: false, reason: `page answered ${response.status}` };
    const html = await response.text();
    const match =
      html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
      html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
    return match ? { ok: true, image: match[1] } : { ok: false, reason: 'no preview image on the page' };
  } catch (error) {
    return { ok: false, reason: error.name === 'TimeoutError' ? 'page took too long' : error.message };
  }
}

// "https://www.cos.com/nl-nl/" becomes "cos.com/nl-nl": the store's domain and its country part.
function searchDomain(website) {
  const url = new URL(website);
  const host = url.hostname.replace(/^www\./, '');
  const firstPart = url.pathname.split('/').filter(Boolean)[0];
  return firstPart && /^[a-z]{2}([-_][a-z]{2})?$/i.test(firstPart) ? `${host}/${firstPart}` : host;
}

async function findWebsites({ models, stores, countries, results }) {
  results.websites = results.websites || {};
  for (const code of countries) {
    const country = COUNTRIES[code];
    results.websites[code] = results.websites[code] || {};
    for (const model of models) {
      console.log(`\nStore websites for ${country.name}, ${MODELS[model].label}`);
      const run = [];
      for (const store of stores) {
        try {
          const answer = await searchAndFill({
            model,
            test: '4-stores',
            action: 'store website',
            system: WEBSITE_SYSTEM,
            prompt: websitePrompt(store, country),
            schema: WEBSITE_SCHEMA,
            toolOptions: { max_uses: 3, user_location: country.location },
          });
          const d = answer.data;
          run.push({ store, data: d, way: answer.way, notes: answer.notes, searches: answer.usage.webSearches, seconds: answer.seconds, cost: answer.cost });
          const line = d ? `${d.website || 'no website'} · sells online: ${d.sells_online} · ${d.currency || 'no currency'}` : 'no answer';
          console.log(`  ${store}: ${line}  (${answer.usage.webSearches} searches, ${answer.seconds.toFixed(1)} s, ${dollars(answer.cost)})`);
        } catch (error) {
          run.push({ store, error: describeError(error) });
          console.log(`  ${store} failed: ${describeError(error)}`);
          if (/did not work for/.test(error.message)) break; // this model cannot search; skip its other stores
        }
      }
      results.websites[code][model] = run;
      saveJson('stores.json', results);
    }
  }
}

function knownWebsite(results, code, store) {
  const byModel = (results.websites && results.websites[code]) || {};
  for (const model of ['opus', 'sonnet', 'haiku']) {
    const found = (byModel[model] || []).find((r) => r.store.toLowerCase() === store.toLowerCase() && r.data && r.data.website);
    if (found) return found.data.website;
  }
  return null;
}

async function searchPiece({ models, countries, piece, store, results }) {
  results.search = results.search || {};
  results.search.piece = piece;
  results.search.store = store;
  for (const code of countries) {
    const country = COUNTRIES[code];
    const website = knownWebsite(results, code, store);
    if (!website) {
      console.log(`\nNo ${store} website for ${country.name} yet. Run the websites part first: npm run spike:stores -- --part websites --stores "${store}"`);
      continue;
    }
    const domain = searchDomain(website);
    results.search[code] = results.search[code] || {};
    for (const model of models) {
      console.log(`\nSearching ${domain} for "${piece}", ${MODELS[model].label}`);
      try {
        const answer = await searchAndFill({
          model,
          test: '4-stores',
          action: 'store search',
          system: SEARCH_SYSTEM,
          prompt: searchPrompt(store, country, piece),
          schema: SEARCH_SCHEMA,
          toolOptions: { max_uses: 3, allowed_domains: [domain], user_location: country.location },
        });
        const products = (answer.data && answer.data.products) || [];
        const images = [];
        for (const product of products) {
          images.push(product.image_url ? { ok: true, image: product.image_url, from: 'search' } : { ...(await previewImage(product.url)), from: 'page' });
        }
        results.search[code][model] = {
          domain,
          products,
          images,
          way: answer.way,
          notes: answer.notes,
          searches: answer.usage.webSearches,
          seconds: answer.seconds,
          cost: answer.cost,
        };
        if (products.length === 0) console.log('  Nothing found');
        products.forEach((p, i) => {
          const image = images[i].ok ? `image from the ${images[i].from}` : `no image (${images[i].reason})`;
          console.log(`  ${p.name} · ${p.price} ${p.currency} · ${p.url} · ${image}`);
        });
        console.log(`  ${answer.usage.webSearches} searches, ${answer.seconds.toFixed(1)} s, ${dollars(answer.cost)}, ${answer.way}`);
      } catch (error) {
        results.search[code][model] = { domain, error: describeError(error) };
        console.log(`  failed: ${describeError(error)}`);
      }
      saveJson('stores.json', results);
    }
  }
}

async function main() {
  const options = readOptions();
  const models = pickModels(options.model);
  const part = options.part || 'both';
  const stores = options.stores ? String(options.stores).split(',').map((s) => s.trim()) : STORES;
  const countries = options.country ? [String(options.country).toUpperCase()] : Object.keys(COUNTRIES);
  const results = loadJson('stores.json', {});

  if (part === 'both' || part === 'websites') {
    await findWebsites({ models, stores, countries, results });
  }
  if (part === 'both' || part === 'search') {
    if (!options.piece || options.piece === true) {
      console.log('\nTo search for a piece, add it like this: npm run spike:stores -- --part search --piece "black leather loafers"');
    } else {
      await searchPiece({ models, countries, piece: options.piece, store: options['search-store'] || 'COS', results });
    }
  }

  console.log('\nSaved to server/spike/results/stores.json.');
}

main();
