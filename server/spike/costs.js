// npm run spike:costs
// Adds up the cost log: what each action costs per model, on average, and how long it takes.
// Also projects two numbers that matter for the app: a first wardrobe of 100 pieces,
// and a look from a photo once the wardrobe has 100 pieces.

const { MODELS } = require('./lib/claude');
const { readCostLog, saveJson, dollars } = require('./lib/output');

function average(values) {
  return values.length ? values.reduce((sum, v) => sum + v, 0) / values.length : 0;
}

function groupName(entry) {
  let name = entry.action;
  if (entry.action === 'piece details' && entry.note) name += `, photo ${entry.note.replace('size ', '')} px`;
  if (/look from a photo|inspiration/.test(entry.action)) name += entry.cache_read_tokens > 0 ? ', wardrobe from cache' : ', first call';
  return name;
}

function main() {
  const log = readCostLog();
  if (log.length === 0) {
    console.log('No calls logged yet.');
    return;
  }

  const groups = {};
  for (const entry of log) {
    const key = `${groupName(entry)}|${entry.model}`;
    (groups[key] = groups[key] || []).push(entry);
  }

  const rows = Object.entries(groups)
    .map(([key, entries]) => {
      const [action, model] = key.split('|');
      return {
        action,
        model: MODELS[model] ? MODELS[model].label : model,
        modelKey: model,
        calls: entries.length,
        prompt_tokens: Math.round(average(entries.map((e) => e.input_tokens + e.cache_write_tokens + e.cache_read_tokens))),
        cache_write_tokens: Math.round(average(entries.map((e) => e.cache_write_tokens))),
        cache_read_tokens: Math.round(average(entries.map((e) => e.cache_read_tokens))),
        output_tokens: Math.round(average(entries.map((e) => e.output_tokens))),
        thinking_tokens: Math.round(average(entries.map((e) => e.thinking_tokens || 0))),
        web_searches: average(entries.map((e) => e.web_searches)),
        seconds: average(entries.map((e) => e.seconds)),
        cost: average(entries.map((e) => e.cost)),
      };
    })
    .sort((a, b) => a.action.localeCompare(b.action) || a.model.localeCompare(b.model));

  console.log('Average per call\n');
  console.log(['Action'.padEnd(46), 'Model'.padEnd(11), 'Calls'.padEnd(6), 'Tokens in'.padEnd(10), 'Out'.padEnd(7), 'Seconds'.padEnd(8), 'Cost'].join(''));
  for (const r of rows) {
    console.log(
      [
        r.action.padEnd(46),
        r.model.padEnd(11),
        String(r.calls).padEnd(6),
        String(r.prompt_tokens).padEnd(10),
        String(r.output_tokens).padEnd(7),
        r.seconds.toFixed(1).padEnd(8),
        dollars(r.cost),
      ].join(''),
    );
  }

  // Projections.
  const projections = {};
  console.log('\nProjections');
  for (const [key, model] of Object.entries(MODELS)) {
    const details = rows.find((r) => r.modelKey === key && r.action === 'piece details, photo 1568 px');
    const first = rows.find((r) => r.modelKey === key && r.action === 'look from a photo, first call');
    const cached = rows.find((r) => r.modelKey === key && r.action === 'look from a photo, wardrobe from cache');
    const p = {};
    if (details) p.first_wardrobe_100_pieces = details.cost * 100;
    if (first && first.cache_write_tokens) {
      // The cached part is the instructions plus the wardrobe; most of it is the 15 pieces.
      const perPiece = first.cache_write_tokens / 15;
      const extra = perPiece * 85;
      p.look_at_100_pieces_first = first.cost + (extra * model.price.cacheWrite) / 1e6;
      if (cached) p.look_at_100_pieces_cached = cached.cost + (extra * model.price.cacheRead) / 1e6;
      p.tokens_per_wardrobe_piece = Math.round(perPiece);
    }
    projections[model.label] = p;
    const parts = [];
    if (p.first_wardrobe_100_pieces !== undefined) parts.push(`first wardrobe of 100 pieces ${dollars(p.first_wardrobe_100_pieces)}`);
    if (p.look_at_100_pieces_first !== undefined) parts.push(`a look from a photo with 100 pieces ${dollars(p.look_at_100_pieces_first)}`);
    if (p.look_at_100_pieces_cached !== undefined) parts.push(`${dollars(p.look_at_100_pieces_cached)} when the wardrobe is cached`);
    if (parts.length) console.log(`  ${model.label}: ${parts.join(', ')}`);
  }

  const total = log.reduce((sum, e) => sum + e.cost, 0);
  console.log(`\nThe spike so far: ${log.length} calls, ${dollars(total)} in all.`);
  saveJson('costs-summary.json', { rows, projections, total, calls: log.length });
}

main();
