// Cities, for onboarding step 2 (PRD sections 5 and 9).
//
// City search comes from Open-Meteo's free geocoding service (no key needed), the same one
// the T1 spike used. It is built on GeoNames, a public list of places, so "Miami" comes back
// as Miami, Florida, United States, with its coordinates and time zone. The server asks it,
// never the app, so the app only ever talks to Caro's own server.
//
// A city a member chooses is kept in the cities table. Its weather is added by weather.js.

const db = require('../db');
const { now, iso } = require('./today');

const GEOCODING = 'https://geocoding-api.open-meteo.com/v1';

class PlaceError extends Error {}

async function getJson(url) {
  let response;
  try {
    response = await fetch(url, { signal: AbortSignal.timeout(10000) });
  } catch {
    throw new PlaceError('City search could not be reached.');
  }
  if (!response.ok) throw new PlaceError(`City search answered ${response.status}.`);
  return response.json();
}

// The parts that ask another service. The tests replace them, so they never use the network.
const remote = {
  // Up to six places matching a name, biggest first. countryCode narrows it to one country.
  async search(name, countryCode) {
    const country = countryCode ? `&countryCode=${encodeURIComponent(countryCode)}` : '';
    const data = await getJson(`${GEOCODING}/search?name=${encodeURIComponent(name)}&count=6&language=en&format=json${country}`);
    return data.results || [];
  },

  // One place by its GeoNames id, or null.
  async byId(id) {
    const data = await getJson(`${GEOCODING}/get?id=${encodeURIComponent(id)}&language=en&format=json`);
    return data && data.id ? data : null;
  },
};

// Open-Meteo's answer, in the shape Caro keeps.
function placeFrom(result) {
  return {
    id: result.id,
    name: result.name,
    region: result.admin1 || null,
    country: (result.country_code || '').toUpperCase(),
    latitude: result.latitude,
    longitude: result.longitude,
    timezone: result.timezone || null,
  };
}

// What the app is told about a city.
function cityJSON(city) {
  return { id: city.id, name: city.name, region: city.region, country: city.country };
}

// "Miami, Florida" searches for "Miami": the search wants a place name only.
async function searchCities(query) {
  const name = String(query || '').split(',')[0].trim();
  if (name.length < 2) return [];
  const results = await remote.search(name);
  return results.filter((r) => r.country_code && typeof r.latitude === 'number').map(placeFrom).map(cityJSON);
}

function saveCity(place) {
  db.prepare(
    `INSERT INTO cities (id, name, region, country, latitude, longitude, timezone, created_at)
     VALUES (@id, @name, @region, @country, @latitude, @longitude, @timezone, @createdAt)
     ON CONFLICT (id) DO NOTHING`
  ).run({ ...place, createdAt: iso(now()) });
  return db.prepare('SELECT * FROM cities WHERE id = ?').get(place.id);
}

// A city by its id: from the cities table, or else looked up once and kept. Null if unknown.
async function cityById(id) {
  const cityId = Number(id);
  if (!Number.isInteger(cityId) || cityId <= 0) return null;
  const saved = db.prepare('SELECT * FROM cities WHERE id = ?').get(cityId);
  if (saved) return saved;
  const result = await remote.byId(cityId);
  return result ? saveCity(placeFrom(result)) : null;
}

// The member's city. Members set up before T4 (Marta, from the seed) have a city name but no
// city row: it is found once by name and country, and remembered.
async function cityForMember(member) {
  if (member.city_id) return cityById(member.city_id);
  if (!member.city || !member.country) return null;
  const [first] = await remote.search(member.city, member.country);
  if (!first) return null;
  const city = saveCity(placeFrom(first));
  db.prepare('UPDATE users SET city_id = ? WHERE id = ?').run(city.id, member.id);
  return city;
}

module.exports = { PlaceError, remote, searchCities, cityById, cityForMember, cityJSON, saveCity };
