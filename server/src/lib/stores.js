// A member's stores (PRD sections 5 and 9): finding a store's website for their country.
//
// Haiku with web search, as chosen in the T1 spike: it searched before answering, where the
// larger models often answered from memory and got some addresses wrong. About 2 cents and
// 3 to 20 seconds per store. The prompt and form start from server/spike/4-stores.js.
// Stores are a personal list: no shared catalogue, so nothing here is kept for other members.

const { ask } = require('./claude');

const SYSTEM = `You help a person set up the list of stores they shop at. You look up facts about stores on the web.
You never recommend stores or products.`;

const SCHEMA = {
  type: 'object',
  properties: {
    found: { type: 'boolean' },
    official_name: { type: 'string' },
    domain: { type: 'string' },
    website: { type: 'string' },
    sells_online: { type: 'string', enum: ['yes', 'no', 'not sure'] },
    evidence: { type: 'string' },
  },
  required: ['found', 'official_name', 'domain', 'website', 'sells_online', 'evidence'],
  additionalProperties: false,
};

const countryNames = new Intl.DisplayNames(['en'], { type: 'region' });

function prompt(store, country, currency) {
  const place = countryNames.of(country);
  return `Find the official online shop of the store "${store}" for someone who lives in ${place}.

- found: whether you found the store's official website
- official_name: the store's name as people write it in a sentence, like Zara, COS or Arket
- domain: the store's main web address without www, like cos.com, even if it has no shop for ${place}
- website: the address of its online shop for ${place}, including the country part of the address if it has one, like https://www.example.com/nl-nl/. Empty if there is none.
- sells_online: "yes" if people in ${place} can buy from it online${currency ? `, with prices in ${currency}` : ''}; "no" if it has no online shop for ${place}; "not sure" if you cannot tell
- evidence: one short sentence on what you found`;
}

// "https://www.cos.com/en-us/" becomes "cos.com". Null if it is not a web address.
function domainOf(address) {
  try {
    const url = new URL(/^https?:\/\//i.test(address) ? address : `https://${address}`);
    const host = url.hostname.toLowerCase().replace(/^www\./, '');
    return /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(host) ? host : null;
  } catch {
    return null;
  }
}

// A shop address the app can open: https only. Null otherwise.
function shopUrl(address) {
  try {
    const url = new URL(address);
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

// The parts that ask another service. The tests replace them, so they cost nothing.
const remote = {
  claude(store, country, currency) {
    return ask({
      model: 'haiku',
      system: SYSTEM,
      prompt: prompt(store, country, currency),
      schema: SCHEMA,
      tools: [{ type: 'web_search_20260209', name: 'web_search', max_uses: 3, user_location: { type: 'approximate', country } }],
    });
  },
};

// What Caro found for a store in a country, ready to show on the card in step 4.
// { found, name, domain, countryUrl, sellsOnline, country }
async function findWebsite(name, country, currency) {
  const answer = await remote.claude(name, country, currency);
  const countryUrl = answer.website ? shopUrl(answer.website) : null;
  const domain = domainOf(answer.domain || '') || (countryUrl && domainOf(countryUrl));

  if (!answer.found || !domain) {
    return { found: false, name };
  }

  // "not sure" with a shop address counts as yes: the store search will find out.
  const sellsOnline = answer.sells_online === 'yes' || (answer.sells_online === 'not sure' && Boolean(countryUrl));
  return {
    found: true,
    name: (answer.official_name || name).trim().slice(0, 60),
    domain,
    countryUrl: sellsOnline ? countryUrl : null,
    sellsOnline: sellsOnline && Boolean(countryUrl),
    country,
  };
}

module.exports = { remote, findWebsite, domainOf, shopUrl };
