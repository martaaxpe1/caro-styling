// A member's year: four seasons, two, or none (PRD sections 5 and 9).
//
// A rule in code proposes it from the city's typical weather, not the AI. In the T1 spike it
// proposed the right year in all six places tried; the models were less steady.
// - Four meteorological seasons when the typical highs vary by 10 °C or more over the year,
//   shifted by six months in the southern hemisphere.
// - Otherwise two, when most of the rain (65% or more) falls in six months in a row, named
//   from the temperature and rain, like "Hot and rainy" and "Mild and dry".
// - Otherwise none.
//
// All three are worked out, so the member can switch between them in step 3.
// Months are numbers: 1 is January.

const RANGE_FOR_FOUR_C = 10;
const RAIN_SHARE_FOR_TWO = 0.65;

const average = (values) => values.reduce((sum, v) => sum + v, 0) / values.length;

// Six months in a row from a start month, wrapping round the year: 11 gives 11, 12, 1, 2, 3, 4.
function sixFrom(start) {
  return [0, 1, 2, 3, 4, 5].map((k) => ((start - 1 + k) % 12) + 1);
}

function otherSix(months) {
  return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].filter((m) => !months.includes(m));
}

// The other half, in order from the month after the first half ends.
function restFrom(half) {
  const last = half[half.length - 1];
  return sixFrom((last % 12) + 1).filter((m) => otherSix(half).includes(m));
}

function fourSeasons(latitude) {
  const north = [
    ['Spring', [3, 4, 5]],
    ['Summer', [6, 7, 8]],
    ['Autumn', [9, 10, 11]],
    ['Winter', [12, 1, 2]],
  ];
  const shift = (m) => (latitude >= 0 ? m : ((m + 5) % 12) + 1);
  return north.map(([name, months]) => ({ name, months: months.map(shift) }));
}

// The six months in a row with the largest share of something (rain, or warmth).
function bestSix(values) {
  let best = { start: 1, total: -Infinity };
  for (let start = 1; start <= 12; start++) {
    const total = sixFrom(start).reduce((sum, m) => sum + values[m - 1], 0);
    if (total > best.total) best = { start, total };
  }
  return best;
}

// A word for a half of the year from its typical high: Hot or Warm for the warmer half,
// Mild or Cool for the cooler one.
function warmthWord(highs, months, warmer) {
  const high = average(months.map((m) => highs[m - 1]));
  if (warmer) return high >= 28 ? 'Hot' : 'Warm';
  return high >= 15 ? 'Mild' : 'Cool';
}

// Two seasons: by rain when most of it falls in six months, otherwise warm half and cool half.
function twoSeasons(highs, rain) {
  const totalRain = rain.reduce((sum, r) => sum + r, 0);
  const wettest = bestSix(rain);
  const rainShare = totalRain > 0 ? wettest.total / totalRain : 0;

  if (rainShare >= RAIN_SHARE_FOR_TWO) {
    const wet = sixFrom(wettest.start);
    const dry = restFrom(wet);
    const wetIsWarmer = average(wet.map((m) => highs[m - 1])) >= average(dry.map((m) => highs[m - 1]));
    return {
      rainShare,
      seasons: [
        { name: `${warmthWord(highs, wet, wetIsWarmer)} and rainy`, months: wet },
        { name: `${warmthWord(highs, dry, !wetIsWarmer)} and dry`, months: dry },
      ],
    };
  }

  const warm = sixFrom(bestSix(highs).start);
  const cool = restFrom(warm);
  return {
    rainShare,
    seasons: [
      { name: warmthWord(highs, warm, true), months: warm },
      { name: warmthWord(highs, cool, false), months: cool },
    ],
  };
}

// months: the 12 { month, highC, rainMm } from weather.js. latitude: below 0 is the south.
function proposeYear(months, latitude) {
  const highs = months.map((m) => m.highC);
  const rain = months.map((m) => m.rainMm);
  const range = Math.max(...highs) - Math.min(...highs);
  const two = twoSeasons(highs, rain);

  let suggested = 'none';
  if (range >= RANGE_FOR_FOUR_C) suggested = 'four';
  else if (two.rainShare >= RAIN_SHARE_FOR_TWO) suggested = 'two';

  return {
    suggested,
    options: { four: fourSeasons(latitude), two: two.seasons, none: [] },
  };
}

// Checks a year the member confirmed. Returns the tidied seasons, or { error }.
// Four, two or none; every month in exactly one season; each season a name and a month.
function checkSeasons(input) {
  if (!Array.isArray(input) || ![0, 2, 4].includes(input.length)) {
    return { error: 'Choose four seasons, two, or none.' };
  }

  const seasons = input.map((season) => ({
    name: String(season?.name ?? '').trim(),
    months: Array.isArray(season?.months) ? season.months.map(Number) : [],
  }));

  if (seasons.some((s) => !s.name)) return { error: 'Every season needs a name.' };
  if (seasons.some((s) => s.name.length > 30)) return { error: 'Keep season names to 30 letters.' };
  const names = new Set(seasons.map((s) => s.name.toLowerCase()));
  if (names.size !== seasons.length) return { error: 'Give each season its own name.' };
  if (seasons.some((s) => s.months.length === 0)) return { error: 'Every season needs at least one month.' };

  if (seasons.length > 0) {
    const all = seasons.flatMap((s) => s.months).sort((a, b) => a - b);
    const everyMonthOnce = all.length === 12 && all.every((m, i) => m === i + 1);
    if (!everyMonthOnce) return { error: 'Every month belongs to one season.' };
  }

  return { seasons };
}

module.exports = { proposeYear, checkSeasons };
