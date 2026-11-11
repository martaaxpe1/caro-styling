// A city's typical weather: the daily high and the rain for each month (PRD section 9).
//
// Two sources, asked at the same time:
// - Claude's memory (Sonnet). The T1 spike found it within 0.4 °C of the official numbers,
//   small places included.
// - Open-Meteo's weather history for 1991 to 2020, averaged per month. Free, but it runs a
//   little cold, because it averages over a square of land.
// If they differ by more than 3 °C in any month, Open-Meteo's numbers are used; otherwise
// Claude's. If one source fails, the other is used. If Open-Meteo was the one that failed,
// it is asked again the next time anyone needs that city.
//
// The answer is kept in city_weather, so each city is looked up once (a cache).

const db = require('../db');
const { now, iso } = require('./today');
const { ask, recordAiAction } = require('./claude');

const SHORT = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const MAX_DIFFERENCE_C = 3;

class WeatherError extends Error {}

// The form Claude fills in: a high and the rain for each month.
const MEMORY_SCHEMA = {
  type: 'object',
  properties: Object.fromEntries(
    SHORT.map((m) => [
      m,
      {
        type: 'object',
        properties: { high_c: { type: 'number' }, rain_mm: { type: 'number' } },
        required: ['high_c', 'rain_mm'],
        additionalProperties: false,
      },
    ])
  ),
  required: SHORT,
  additionalProperties: false,
};

const SYSTEM = `You help a person set up their wardrobe for the place they live. You know climates well.
You only describe weather. You never give clothing or styling advice.`;

const countryNames = new Intl.DisplayNames(['en'], { type: 'region' });

// "Miami, Florida, United States", so a small place is not mixed up with another.
function placeName(city) {
  return [city.name, city.region, countryNames.of(city.country)].filter(Boolean).join(', ');
}

// Twelve months, each { month: 1 to 12, highC, rainMm }, or an error if anything looks wrong.
function checkedMonths(months) {
  const ok =
    Array.isArray(months) &&
    months.length === 12 &&
    months.every(
      (m) => Number.isFinite(m.highC) && m.highC > -60 && m.highC < 60 && Number.isFinite(m.rainMm) && m.rainMm >= 0 && m.rainMm < 3000
    );
  if (!ok) throw new WeatherError('The monthly numbers do not look right.');
  return months.map((m, i) => ({ month: i + 1, highC: Math.round(m.highC * 10) / 10, rainMm: Math.round(m.rainMm) }));
}

// Daily weather turned into 12 months: the average daily high, and the average rain per month.
function monthlyAverages(dates, highs, rains) {
  const highsByMonth = SHORT.map(() => []);
  const rainByYearMonth = {};
  dates.forEach((day, i) => {
    const month = Number(day.slice(5, 7)) - 1;
    if (highs[i] !== null) highsByMonth[month].push(highs[i]);
    const key = day.slice(0, 7);
    rainByYearMonth[key] = (rainByYearMonth[key] || 0) + (rains[i] || 0);
  });
  const average = (values) => values.reduce((sum, v) => sum + v, 0) / values.length;
  return SHORT.map((_, month) => {
    const rains = Object.entries(rainByYearMonth)
      .filter(([key]) => Number(key.slice(5, 7)) - 1 === month)
      .map(([, total]) => total);
    return { month: month + 1, highC: average(highsByMonth[month]), rainMm: average(rains) };
  });
}

// The parts that ask another service. The tests replace them, so they cost nothing.
const remote = {
  async claude(city) {
    const data = await ask({
      model: 'sonnet',
      system: SYSTEM,
      prompt:
        `From what you know of the climate normals for ${placeName(city)} ` +
        `(latitude ${city.latitude}, longitude ${city.longitude}), give the typical daily high in °C ` +
        'and the typical rain in mm for each month.',
      schema: MEMORY_SCHEMA,
    });
    return SHORT.map((m, i) => ({ month: i + 1, highC: data[m].high_c, rainMm: data[m].rain_mm }));
  },

  // 30 years of daily highs and rain. A large request: Open-Meteo can take a few seconds.
  async openMeteo(city) {
    const url =
      'https://archive-api.open-meteo.com/v1/archive' +
      `?latitude=${city.latitude}&longitude=${city.longitude}` +
      '&start_date=1991-01-01&end_date=2020-12-31' +
      '&daily=temperature_2m_max,precipitation_sum&timezone=auto';
    const response = await fetch(url, { signal: AbortSignal.timeout(45000) });
    if (!response.ok) throw new WeatherError(`Open-Meteo answered ${response.status}.`);
    const data = await response.json();
    return monthlyAverages(data.daily.time, data.daily.temperature_2m_max, data.daily.precipitation_sum);
  },
};

async function fromClaude(city, memberId) {
  try {
    const months = checkedMonths(await remote.claude(city));
    recordAiAction(memberId, 'your year');
    return months;
  } catch (error) {
    console.error(`Weather for ${city.name} from Claude failed: ${error.message}`);
    return null;
  }
}

async function fromOpenMeteo(city) {
  try {
    return checkedMonths(await remote.openMeteo(city));
  } catch (error) {
    console.error(`Weather for ${city.name} from Open-Meteo failed: ${error.message}`);
    return null;
  }
}

function differ(a, b) {
  return a.some((m, i) => Math.abs(m.highC - b[i].highC) > MAX_DIFFERENCE_C);
}

function savedMonths(cityId) {
  const rows = db.prepare('SELECT month, high_c, rain_mm FROM city_weather WHERE city_id = ? ORDER BY month').all(cityId);
  return rows.length === 12 ? rows.map((r) => ({ month: r.month, highC: r.high_c, rainMm: r.rain_mm })) : null;
}

const save = db.transaction((cityId, months, source, checked) => {
  db.prepare('DELETE FROM city_weather WHERE city_id = ?').run(cityId);
  const add = db.prepare('INSERT INTO city_weather (city_id, month, high_c, rain_mm) VALUES (?, ?, ?, ?)');
  for (const m of months) add.run(cityId, m.month, m.highC, m.rainMm);
  db.prepare('UPDATE cities SET weather_source = ?, weather_checked = ?, weather_at = ? WHERE id = ?').run(
    source,
    checked ? 1 : 0,
    iso(now()),
    cityId
  );
});

// The 12 months for a city. memberId is who asked, for the AI usage count.
async function typicalWeather(city, memberId) {
  const saved = savedMonths(city.id);
  const current = db.prepare('SELECT weather_source, weather_checked FROM cities WHERE id = ?').get(city.id);

  if (saved && current.weather_checked) return saved;

  if (saved) {
    // Claude's numbers, kept while Open-Meteo could not be reached: check them now if it can.
    const check = await fromOpenMeteo(city);
    if (check) {
      const useCheck = differ(saved, check);
      save(city.id, useCheck ? check : saved, useCheck ? 'open-meteo' : 'claude', true);
      return useCheck ? check : saved;
    }
    return saved;
  }

  const [claude, openMeteo] = await Promise.all([fromClaude(city, memberId), fromOpenMeteo(city)]);

  if (claude && openMeteo) {
    const useOpenMeteo = differ(claude, openMeteo);
    if (useOpenMeteo) console.log(`Weather for ${city.name}: Claude and Open-Meteo differ by more than 3 °C, using Open-Meteo.`);
    save(city.id, useOpenMeteo ? openMeteo : claude, useOpenMeteo ? 'open-meteo' : 'claude', true);
    return useOpenMeteo ? openMeteo : claude;
  }
  if (claude) {
    save(city.id, claude, 'claude', false);
    return claude;
  }
  if (openMeteo) {
    save(city.id, openMeteo, 'open-meteo', true);
    return openMeteo;
  }
  throw new WeatherError(`Caro could not look up the typical weather in ${city.name}. Try again.`);
}

module.exports = { WeatherError, remote, typicalWeather, monthlyAverages };
