// npm run spike:year
// Test 5: proposing a year of seasons for a city.
// For each city it compares four sources of typical weather, month by month:
//   - official normals from the national weather service (typed in below, 1991 to 2020)
//   - Open-Meteo: free, no key; daily history 1991 to 2020, averaged per month here
//   - NASA POWER: free, no key; daily history 1991 to 2020 for the same point
//   - each Claude model, from memory
// Then it proposes a year two ways: a simple rule in code, and each model given the data.
//
// Options:
//   --model opus,haiku   only these models (default: all three)
//   --no-ai              only the climate data and the rule; costs nothing
//   --cities Vlissingen  only these places (default: Amsterdam, Miami, Buenos Aires)
//   --small-places       the smaller places, to check the models' memory beyond famous cities

const { ask, pickModels, describeError, MODELS } = require('./lib/claude');
const { saveJson, loadJson, readOptions, dollars } = require('./lib/output');

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const SHORT = MONTHS.map((m) => m.slice(0, 3).toLowerCase());

// Official 1991 to 2020 normals: mean daily high in °C and rain in mm per month.
// Copied from the climate tables on Wikipedia, which cite these services.
const CITIES = [
  {
    name: 'Amsterdam',
    country: 'NL',
    official: {
      source: 'KNMI, Amsterdam Airport Schiphol, 1991 to 2020',
      high: [6.2, 6.9, 10.1, 14.3, 17.8, 20.3, 22.5, 22.4, 19.2, 14.7, 10.0, 6.9],
      rain: [66.5, 54.7, 51.8, 39.6, 53.9, 64.8, 82.3, 98.6, 84.4, 86.7, 85.3, 81.7],
    },
  },
  {
    name: 'Miami',
    country: 'US',
    official: {
      source: 'NOAA, Miami International Airport, 1991 to 2020',
      high: [24.6, 25.7, 27.0, 28.7, 30.4, 31.8, 32.6, 32.6, 31.7, 29.9, 27.4, 25.7],
      rain: [46, 55, 62, 85, 161, 267, 187, 243, 260, 194, 90, 62],
    },
  },
  {
    name: 'Buenos Aires',
    country: 'AR',
    official: {
      source: 'Servicio Meteorológico Nacional, Observatorio Central, 1991 to 2020',
      high: [30.1, 28.9, 27.0, 23.2, 19.4, 16.4, 15.5, 17.9, 19.7, 22.6, 26.0, 29.0],
      rain: [134.4, 129.3, 120.0, 130.3, 93.5, 61.5, 74.4, 70.3, 80.6, 122.9, 117.6, 122.8],
    },
  },
  // Smaller places, to check whether the models' memory holds beyond famous cities.
  {
    name: 'Vlissingen',
    country: 'NL',
    small: true,
    official: {
      source: 'KNMI, Vlissingen, 1991 to 2020',
      high: [6.4, 6.8, 9.6, 13.3, 16.8, 19.6, 21.8, 22.0, 19.0, 14.8, 10.4, 7.2],
      rain: [58.9, 52.8, 44.6, 35.0, 49.4, 62.0, 72.4, 81.8, 73.6, 73.8, 78.9, 75.7],
    },
  },
  {
    name: 'Vero Beach',
    country: 'US',
    small: true,
    official: {
      source: 'NOAA, Vero Beach Regional Airport, 1991 to 2020 (converted from °F and inches)',
      high: [22.9, 24.2, 25.8, 27.7, 29.8, 31.6, 32.5, 32.6, 31.3, 29.3, 26.3, 24.1],
      rain: [69.6, 55.9, 87.4, 77.7, 106.7, 171.7, 144.3, 186.7, 178.8, 135.4, 73.9, 64.5],
    },
  },
  {
    name: 'Mar del Plata',
    country: 'AR',
    small: true,
    official: {
      source: 'Servicio Meteorológico Nacional, Mar del Plata, 1991 to 2020',
      high: [26.4, 25.5, 23.8, 20.4, 16.9, 13.8, 12.6, 14.7, 15.9, 18.6, 21.7, 25.2],
      rain: [91.1, 103.6, 95.2, 97.3, 60.0, 66.1, 57.8, 63.6, 63.1, 83.1, 80.3, 84.8],
    },
  },
];

// Open-Meteo's free tier allows only so much data per minute, and 30 years of daily
// weather counts as a lot. When it says "too many requests", wait a minute and try once more.
async function getJson(url, { retry = true } = {}) {
  const response = await fetch(url, { signal: AbortSignal.timeout(120000) });
  if (response.status === 429 && retry) {
    console.log(`  ${new URL(url).hostname} asks to slow down; waiting a minute`);
    await new Promise((resolve) => setTimeout(resolve, 65000));
    return getJson(url, { retry: false });
  }
  if (!response.ok) throw new Error(`${new URL(url).hostname} answered ${response.status}`);
  return response.json();
}

// City search, the way onboarding step 2 could do it.
async function findCity(city) {
  const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city.name)}&countryCode=${city.country}&count=1&language=en&format=json`;
  const data = await getJson(url);
  if (!data.results || data.results.length === 0) throw new Error(`Open-Meteo did not find ${city.name}`);
  const place = data.results[0];
  return { latitude: place.latitude, longitude: place.longitude, country: place.country, timezone: place.timezone };
}

// Open-Meteo: 30 years of daily highs and rain, turned into 12 monthly averages.
async function openMeteo(place) {
  const url =
    'https://archive-api.open-meteo.com/v1/archive' +
    `?latitude=${place.latitude}&longitude=${place.longitude}` +
    '&start_date=1991-01-01&end_date=2020-12-31' +
    '&daily=temperature_2m_max,precipitation_sum&timezone=auto';
  const data = await getJson(url);
  return monthlyAverages(data.daily.time, data.daily.temperature_2m_max, data.daily.precipitation_sum);
}

// NASA POWER: 30 years of daily highs and rain for the same point.
// (Its ready-made monthly summary gives the hottest day of each month, not a typical day.)
async function nasaPower(place) {
  const url =
    'https://power.larc.nasa.gov/api/temporal/daily/point' +
    `?parameters=T2M_MAX,PRECTOTCORR&community=AG&longitude=${place.longitude}&latitude=${place.latitude}` +
    '&start=19910101&end=20201231&format=JSON';
  const data = await getJson(url);
  const p = data.properties.parameter;
  const days = Object.keys(p.T2M_MAX);
  const dates = days.map((d) => `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6)}`);
  const missing = (v) => (v === null || v <= -999 ? null : v); // NASA marks missing days as -999
  return monthlyAverages(
    dates,
    days.map((d) => missing(p.T2M_MAX[d])),
    days.map((d) => missing(p.PRECTOTCORR[d])),
  );
}

// Daily weather (dates like 2020-01-31) turned into 12 months: the average daily high,
// and the average rain per month across the years.
function monthlyAverages(dates, highs, rains) {
  const highsByMonth = MONTHS.map(() => []);
  const rainByYearMonth = {};
  dates.forEach((day, i) => {
    const month = Number(day.slice(5, 7)) - 1;
    if (highs[i] !== null) highsByMonth[month].push(highs[i]);
    const key = day.slice(0, 7);
    rainByYearMonth[key] = (rainByYearMonth[key] || 0) + (rains[i] || 0);
  });
  const rain = MONTHS.map((_, month) => {
    const totals = Object.entries(rainByYearMonth)
      .filter(([key]) => Number(key.slice(5, 7)) - 1 === month)
      .map(([, total]) => total);
    return average(totals);
  });
  return { high: highsByMonth.map(average), rain };
}

function average(values) {
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

// Average difference from the official normals, ignoring whether it is above or below.
function offBy(values, official) {
  return average(values.map((v, i) => Math.abs(v - official[i])));
}

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
    ]),
  ),
  required: SHORT,
  additionalProperties: false,
};

const YEAR_SCHEMA = {
  type: 'object',
  properties: {
    seasons_count: { type: 'string', enum: ['four', 'two', 'none'] },
    seasons: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          months: { type: 'array', items: { type: 'string', enum: MONTHS } },
        },
        required: ['name', 'months'],
        additionalProperties: false,
      },
    },
    why: { type: 'string' },
  },
  required: ['seasons_count', 'seasons', 'why'],
  additionalProperties: false,
};

const YEAR_SYSTEM = `You help a person set up their wardrobe for the place they live. You know climates well.
You only describe weather and seasons. You never give clothing or styling advice.`;

function yearPrompt(city, table) {
  return `This is the typical weather in ${city}, month by month (daily high in °C, rain in mm):
${table}

Propose how someone who lives there would divide their year into seasons for their wardrobe. Choose four seasons, two, or none:
- four: the year has a clear cold part and a clear warm part, with changes between them. Use the names Spring, Summer, Autumn and Winter, matched to the local months.
- two: temperatures change little, but another difference matters more, such as a rainy and a dry part of the year. Name each season in two or three words from its weather, like "Hot and rainy" or "Mild and dry".
- none: the weather stays about the same all year. Then seasons is empty.
Each month belongs to exactly one season, and each season is a run of consecutive months.
why: one sentence on what decided it.`;
}

function weatherTable(data) {
  return MONTHS.map((m, i) => `${m}: ${data.high[i].toFixed(1)} °C, ${Math.round(data.rain[i])} mm`).join('\n');
}

// The simple rule: four seasons when highs swing 10 °C or more over the year;
// two when not, but half the year brings most of the rain; otherwise none.
function ruleYear(data, latitude) {
  const range = Math.max(...data.high) - Math.min(...data.high);
  if (range >= 10) {
    const north = [
      ['Spring', [2, 3, 4]],
      ['Summer', [5, 6, 7]],
      ['Autumn', [8, 9, 10]],
      ['Winter', [11, 0, 1]],
    ];
    const seasons = north.map(([name, months]) => ({
      name,
      months: months.map((m) => MONTHS[latitude >= 0 ? m : (m + 6) % 12]),
    }));
    return { seasons_count: 'four', seasons, why: `Highs change by ${range.toFixed(1)} °C over the year.` };
  }

  const total = data.rain.reduce((sum, r) => sum + r, 0);
  let best = { start: 0, share: 0 };
  for (let start = 0; start < 12; start++) {
    const window = [0, 1, 2, 3, 4, 5].map((k) => (start + k) % 12);
    const share = window.reduce((sum, m) => sum + data.rain[m], 0) / total;
    if (share > best.share) best = { start, share };
  }
  if (best.share >= 0.65) {
    const wet = [0, 1, 2, 3, 4, 5].map((k) => (best.start + k) % 12);
    const dry = [6, 7, 8, 9, 10, 11].map((k) => (best.start + k) % 12);
    const warmer = average(wet.map((m) => data.high[m])) >= average(dry.map((m) => data.high[m]));
    const word = (months, isWarmer) => {
      const high = average(months.map((m) => data.high[m]));
      return isWarmer ? (high >= 28 ? 'Hot' : 'Warm') : high >= 15 ? 'Mild' : 'Cool';
    };
    return {
      seasons_count: 'two',
      seasons: [
        { name: `${word(wet, warmer)} and rainy`, months: wet.map((m) => MONTHS[m]) },
        { name: `${word(dry, !warmer)} and dry`, months: dry.map((m) => MONTHS[m]) },
      ],
      why: `Highs change by only ${range.toFixed(1)} °C, and ${Math.round(best.share * 100)}% of the rain falls in six months.`,
    };
  }
  return { seasons_count: 'none', seasons: [], why: `Highs change by only ${range.toFixed(1)} °C and the rain is spread out.` };
}

// "Now: hot and rainy, until the end of October." For today, or DEV_TODAY if set.
function nowLine(year) {
  if (!year || year.seasons.length === 0) return 'No seasons.';
  const today = process.env.DEV_TODAY ? new Date(process.env.DEV_TODAY) : new Date();
  const month = MONTHS[today.getMonth()];
  const season = year.seasons.find((s) => s.months.includes(month));
  if (!season) return 'This month is in no season.';
  return `Now: ${season.name.toLowerCase()}, until the end of ${season.months[season.months.length - 1]}.`;
}

function describeYear(year) {
  if (!year) return 'no answer';
  if (year.seasons.length === 0) return 'none';
  return year.seasons.map((s) => `${s.name} ${s.months[0].slice(0, 3)} to ${s.months[s.months.length - 1].slice(0, 3)}`).join(', ');
}

function fahrenheit(c) {
  return Math.round((c * 9) / 5 + 32);
}

async function main() {
  const options = readOptions();
  const models = options['no-ai'] ? [] : pickModels(options.model);
  const names = options.cities ? String(options.cities).split(',').map((n) => n.trim().toLowerCase()) : null;
  const cities = CITIES.filter((c) => (names ? names.includes(c.name.toLowerCase()) : options['small-places'] ? c.small : !c.small));
  // Earlier results for other places stay; the places run now replace their own.
  const results = loadJson('year.json', { cities: [] });

  for (const city of cities) {
    console.log(`\n${city.name}`);
    const result = { name: city.name, official: city.official, sources: {}, memory: {}, proposals: {} };
    try {
      result.place = await findCity(city);
      console.log(`  Found by Open-Meteo city search: ${result.place.latitude}, ${result.place.longitude}, ${result.place.country}, ${result.place.timezone}`);
    } catch (error) {
      console.log(`  City search failed: ${error.message}`);
      results.cities = [...results.cities.filter((c) => c.name !== city.name), result];
      continue;
    }

    for (const [name, load] of [
      ['Open-Meteo', openMeteo],
      ['NASA POWER', nasaPower],
    ]) {
      try {
        result.sources[name] = await load(result.place);
      } catch (error) {
        console.log(`  ${name} failed: ${error.message}`);
      }
    }

    for (const model of models) {
      try {
        const answer = await ask({
          test: '5-year',
          action: 'climate from memory',
          model,
          effort: 'low',
          system: YEAR_SYSTEM,
          content: `From what you know of the climate normals for ${city.name}, give the typical daily high in °C and the typical rain in mm for each month.`,
          schema: MEMORY_SCHEMA,
        });
        if (answer.data) {
          result.memory[MODELS[model].label] = {
            high: SHORT.map((m) => answer.data[m].high_c),
            rain: SHORT.map((m) => answer.data[m].rain_mm),
            cost: answer.cost,
            seconds: answer.seconds,
          };
        }
      } catch (error) {
        console.log(`  ${MODELS[model].label} from memory failed: ${describeError(error)}`);
      }
    }

    // The table, month by month.
    const columns = [['Official', city.official], ...Object.entries(result.sources), ...Object.entries(result.memory)];
    const us = city.country === 'US';
    console.log(`  Daily high, °C${us ? ' (°F)' : ''}`);
    console.log('  ' + ['Month'.padEnd(10), ...columns.map(([name]) => name.padEnd(12))].join(''));
    MONTHS.forEach((m, i) => {
      const cells = columns.map(([, data]) => `${data.high[i].toFixed(1)}${us ? ` (${fahrenheit(data.high[i])})` : ''}`.padEnd(12));
      console.log('  ' + [m.padEnd(10), ...cells].join(''));
    });
    console.log('  Average difference from the official normals:');
    result.offBy = {};
    for (const [name, data] of columns.slice(1)) {
      result.offBy[name] = { high: offBy(data.high, city.official.high), rain: offBy(data.rain, city.official.rain) };
      console.log(`    ${name}: highs ${result.offBy[name].high.toFixed(1)} °C, rain ${Math.round(result.offBy[name].rain)} mm a month`);
    }

    // The proposed year.
    const data = result.sources['Open-Meteo'] || city.official;
    result.proposals.rule = ruleYear(data, result.place.latitude);
    console.log(`  Proposed year by the rule: ${describeYear(result.proposals.rule)}. ${nowLine(result.proposals.rule)}`);
    for (const model of models) {
      try {
        const answer = await ask({
          test: '5-year',
          action: 'year from data',
          model,
          effort: 'low',
          system: YEAR_SYSTEM,
          content: yearPrompt(city.name, weatherTable(data)),
          schema: YEAR_SCHEMA,
        });
        result.proposals[MODELS[model].label] = { ...answer.data, cost: answer.cost, seconds: answer.seconds };
        console.log(`  Proposed year by ${MODELS[model].label}: ${describeYear(answer.data)}. ${nowLine(answer.data)}  (${dollars(answer.cost)})`);
      } catch (error) {
        console.log(`  ${MODELS[model].label} year failed: ${describeError(error)}`);
      }
    }
    results.cities = [...results.cities.filter((c) => c.name !== city.name), result];
  }

  results.cities.sort((a, b) => CITIES.findIndex((c) => c.name === a.name) - CITIES.findIndex((c) => c.name === b.name));
  saveJson('year.json', results);
  console.log('\nSaved to server/spike/results/year.json.');
}

main();
