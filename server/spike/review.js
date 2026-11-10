// npm run spike:review
// Builds results/review.html: your photos next to what each model said, so you can
// check the answers by eye. Opens it in your browser. The page stays on your Mac.
//
// Options:
//   --no-open   build the page without opening it

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { RESULTS_DIR, loadJson, loadAnswers, dollars } = require('./lib/output');
const { MODELS } = require('./lib/claude');
const { listPhotos } = require('./lib/images');

function esc(value) {
  return String(value === undefined || value === null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const label = (model) => (MODELS[model] ? MODELS[model].label : model);
const img = (src, cls = 'photo') => `<img class="${cls}" src="${esc(src)}" alt="">`;
const pieceThumb = (file) => `prepared/512/pieces/${file}.jpg`;

function detailsSection() {
  const details = loadJson('details-1568.json', null);
  if (!details) return '<p class="muted">Test 1 has not run yet.</p>';
  const models = Object.keys(details.runs);
  const fields = [
    ['Name', (d) => d.name],
    ['Chapter', (d) => d.chapter],
    ['Kind', (d) => d.kind],
    ['Colours', (d) => d.colours.join(', ')],
    ['Pattern', (d) => d.pattern],
    ['Material', (d) => d.material],
    ['Warmth', (d) => d.warmth],
    ['Formality', (d) => d.formality],
    ['Unsure about', (d) => d.unsure_about.join(', ') || 'nothing'],
  ];
  const pieces = listPhotos('pieces');

  return pieces
    .map((piece) => {
      const answers = models.map((m) => details.runs[m].find((r) => r.file === piece.file) || {});
      const rows = fields
        .map(([name, read]) => {
          const values = answers.map((a) => (a.data ? read(a.data) : a.error || 'no answer'));
          const differ = new Set(values).size > 1;
          return `<tr><th>${name}</th>${values.map((v) => `<td class="${differ ? 'differ' : ''}">${esc(v)}</td>`).join('')}</tr>`;
        })
        .join('');
      const notes = answers.map((a) => `<td class="muted">${esc((a.problems || []).join('; '))}</td>`).join('');
      const cost = answers.map((a) => `<td class="muted">${a.seconds ? `${a.seconds.toFixed(1)} s, ${dollars(a.cost)}` : ''}</td>`).join('');
      return `
      <article class="item">
        <div class="pic"><span class="number">${piece.number}</span>${img(`prepared/1568/pieces/${piece.file}.jpg`)}</div>
        <table>
          <tr><th></th>${models.map((m) => `<th>${label(m)}</th>`).join('')}</tr>
          ${rows}
          <tr><th>Flags</th>${notes}</tr>
          <tr><th>Time and cost</th>${cost}</tr>
        </table>
      </article>`;
    })
    .join('');
}

function looksSection() {
  const looks = loadJson('looks.json', null);
  if (!looks) return '<p class="muted">Test 2 has not run yet.</p>';
  const key = loadAnswers().looks || {};
  const pieces = Object.fromEntries(listPhotos('pieces').map((p) => [p.number, p.file]));

  return listPhotos('looks')
    .map((look) => {
      const n = String(Number(look.number));
      const expected = (key[n] || []).map((x) => String(x).padStart(2, '0'));
      const blocks = Object.entries(looks.modes)
        .flatMap(([mode, byModel]) =>
          Object.entries(byModel).map(([model, run]) => {
            const r = run.find((x) => x.file === look.file) || {};
            if (!r.data) return `<div class="answer"><h4>${label(model)}, ${mode}</h4><p class="muted">${esc(r.error || (r.refused ? 'declined' : 'no answer'))}</p></div>`;
            const worn = r.data.worn
              .map((w) => {
                const right = expected.length ? (expected.includes(w.piece) ? 'right' : 'wrong') : '';
                return `<figure class="${right}">${img(pieceThumb(pieces[w.piece]), 'thumb')}<figcaption>${w.piece}, ${w.certainty}</figcaption></figure>`;
              })
              .join('');
            const missed = r.score && r.score.missed.length ? `<p class="flag">Missed: ${r.score.missed.join(', ')}</p>` : '';
            const others = r.data.not_in_wardrobe.map((o) => esc(o.description)).join(', ');
            return `<div class="answer"><h4>${label(model)}, ${mode}</h4><div class="row">${worn || '<span class="muted">nothing spotted</span>'}</div>${missed}
              <p class="muted">Not in the wardrobe: ${others || 'nothing'}. Photo: ${esc(r.data.photo_quality)}. ${r.seconds.toFixed(1)} s, ${dollars(r.cost)}.</p></div>`;
          }),
        )
        .join('');
      const answer = expected.length ? `Your answer key: ${expected.join(', ')}` : 'No answer key yet';
      return `<article class="item"><div class="pic"><span class="number">Look ${n}</span>${img(`prepared/1568/looks/${look.file}.jpg`)}<p class="muted">${answer}</p></div><div>${blocks}</div></article>`;
    })
    .join('');
}

function inspirationsSection() {
  const results = loadJson('inspirations.json', null);
  if (!results) return '<p class="muted">Test 3 has not run yet.</p>';
  const pieces = Object.fromEntries(listPhotos('pieces').map((p) => [p.number, p.file]));

  return listPhotos('inspirations')
    .map((insp) => {
      const n = String(Number(insp.number));
      const blocks = Object.entries(results.modes)
        .flatMap(([mode, byModel]) =>
          Object.entries(byModel).map(([model, run]) => {
            const r = run.find((x) => x.file === insp.file) || {};
            if (!r.data) return `<div class="answer"><h4>${label(model)}, ${mode}</h4><p class="muted">${esc(r.error || (r.refused ? 'declined' : 'no answer'))}</p></div>`;
            const rows = r.data.pieces
              .map((p) => {
                const mine = p.closest_piece === 'none' ? '<span class="flag">Not in your wardrobe</span>' : `${img(pieceThumb(pieces[p.closest_piece]), 'thumb small')} ${p.closest_piece}`;
                return `<tr><td>${esc(p.description)}<br><span class="muted">${esc(p.kind)}, ${esc(p.shape)}</span></td><td class="${p.match}">${p.match}</td><td>${mine}</td></tr>`;
              })
              .join('');
            return `<div class="answer"><h4>${label(model)}, ${mode}</h4><table>${rows}</table><p class="muted">${r.seconds.toFixed(1)} s, ${dollars(r.cost)}</p></div>`;
          }),
        )
        .join('');
      return `<article class="item"><div class="pic"><span class="number">Inspiration ${n}</span>${img(`prepared/1568/inspirations/${insp.file}.jpg`)}</div><div>${blocks}</div></article>`;
    })
    .join('');
}

function storesSection() {
  const stores = loadJson('stores.json', null);
  if (!stores) return '<p class="muted">Test 4 has not run yet.</p>';
  let html = '';
  for (const [country, byModel] of Object.entries(stores.websites || {})) {
    const models = Object.keys(byModel);
    const names = [...new Set(models.flatMap((m) => byModel[m].map((r) => r.store)))];
    html += `<h3>Store websites, ${esc(country)}</h3><table><tr><th>Store</th>${models.map((m) => `<th>${label(m)}</th>`).join('')}</tr>`;
    for (const name of names) {
      html += `<tr><th>${esc(name)}</th>${models
        .map((m) => {
          const r = byModel[m].find((x) => x.store === name) || {};
          if (!r.data) return `<td class="muted">${esc(r.error || '')}</td>`;
          const link = r.data.website ? `<a href="${esc(r.data.website)}">${esc(r.data.website)}</a>` : 'no website';
          return `<td>${link}<br><span class="muted">sells online: ${esc(r.data.sells_online)}, ${esc(r.data.currency)}. ${esc(r.data.evidence)} ${dollars(r.cost)}</span></td>`;
        })
        .join('')}</tr>`;
    }
    html += '</table>';
  }
  if (stores.search) {
    html += `<h3>Search for "${esc(stores.search.piece)}" in ${esc(stores.search.store)}</h3>`;
    for (const [country, byModel] of Object.entries(stores.search)) {
      if (typeof byModel !== 'object') continue;
      for (const [model, r] of Object.entries(byModel)) {
        html += `<h4>${esc(country)}, ${label(model)}, ${esc(r.domain || '')}</h4>`;
        if (r.error) {
          html += `<p class="muted">${esc(r.error)}</p>`;
          continue;
        }
        if (!r.products.length) html += '<p>Nothing found</p>';
        html += '<div class="row">';
        r.products.forEach((p, i) => {
          const image = r.images[i] && r.images[i].ok ? `<img class="thumb" src="${esc(r.images[i].image)}" alt="">` : `<div class="thumb empty">${esc((r.images[i] && r.images[i].reason) || 'no image')}</div>`;
          html += `<figure>${image}<figcaption><a href="${esc(p.url)}">${esc(p.name)}</a><br>${esc(p.price)} ${esc(p.currency)}</figcaption></figure>`;
        });
        html += `</div><p class="muted">${r.searches} searches, ${r.seconds.toFixed(1)} s, ${dollars(r.cost)}, ${esc(r.way)}</p>`;
      }
    }
  }
  return html;
}

function yearSection() {
  const year = loadJson('year.json', null);
  if (!year) return '<p class="muted">Test 5 has not run yet.</p>';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return year.cities
    .map((city) => {
      const columns = [['Official', city.official], ...Object.entries(city.sources || {}), ...Object.entries(city.memory || {})];
      const head = `<tr><th>Daily high, °C</th>${months.map((m) => `<th>${m}</th>`).join('')}</tr>`;
      const rows = columns.map(([name, d]) => `<tr><th>${esc(name)}</th>${d.high.map((h) => `<td>${h.toFixed(1)}</td>`).join('')}</tr>`).join('');
      const proposals = Object.entries(city.proposals || {})
        .map(([who, p]) => {
          const seasons = p.seasons && p.seasons.length ? p.seasons.map((s) => `${esc(s.name)}: ${esc(s.months.join(', '))}`).join('<br>') : 'No seasons';
          return `<tr><th>${esc(who === 'rule' ? 'Simple rule' : who)}</th><td>${seasons}</td><td class="muted">${esc(p.why)}</td></tr>`;
        })
        .join('');
      return `<h3>${esc(city.name)}</h3><table>${head}${rows}</table><table>${proposals}</table>`;
    })
    .join('');
}

function page() {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Caro spike review</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bodoni+Moda:ital@0;1&family=Inter:wght@400;500&display=swap">
<style>
  :root { --paper: #F7F2E9; --ink: #161514; --muted: #6B645C; --hairline: #DCD2C2; --tile: #EFE7DB; --terracotta: #9A5E48; }
  body { margin: 0; padding: 32px 20px 80px; background: var(--paper); color: var(--ink); font: 14px/1.45 Inter, system-ui, sans-serif; }
  h1, h2, h3 { font-family: 'Bodoni Moda', Georgia, serif; font-weight: 400; }
  h1 { font-size: 34px; margin: 0 0 4px; }
  h2 { font-size: 26px; margin: 48px 0 8px; border-top: 3px double var(--ink); padding-top: 12px; }
  h3 { font-size: 21px; margin: 28px 0 8px; }
  h4 { font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase; margin: 0 0 6px; font-weight: 500; }
  .muted { color: var(--muted); }
  .flag { color: var(--terracotta); }
  .item { display: grid; grid-template-columns: 280px 1fr; gap: 24px; padding: 24px 0; border-bottom: 1px solid var(--hairline); }
  .pic { position: relative; }
  .photo { width: 280px; border-radius: 4px; background: var(--tile); display: block; }
  .number { display: block; font-family: 'Bodoni Moda', Georgia, serif; font-size: 30px; margin-bottom: 6px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 12px; }
  th, td { text-align: left; vertical-align: top; padding: 6px 10px 6px 0; border-bottom: 1px solid var(--hairline); }
  th { font-weight: 500; white-space: nowrap; }
  td.differ { color: var(--terracotta); }
  .answer { margin-bottom: 20px; }
  .row { display: flex; flex-wrap: wrap; gap: 12px; }
  figure { margin: 0; width: 110px; font-size: 12px; }
  figure.right img { outline: 2px solid var(--ink); }
  figure.wrong img { outline: 2px solid var(--terracotta); }
  .thumb { width: 110px; height: 110px; object-fit: contain; background: var(--tile); border-radius: 4px; display: block; }
  .thumb.small { width: 48px; height: 48px; display: inline-block; vertical-align: middle; }
  .thumb.empty { display: flex; align-items: center; justify-content: center; text-align: center; color: var(--muted); padding: 8px; box-sizing: border-box; }
  td.yours { color: var(--ink); } td.close { color: var(--muted); } td.missing { color: var(--terracotta); }
  a { color: var(--ink); }
</style>
</head>
<body>
<h1>Spike <em>review</em></h1>
<p class="muted">Your photos next to what each model said. Answers that differ between models are in terracotta. Tell Claude in chat what is wrong, piece by piece. This page stays on your Mac.</p>
<h2>1. Details for your pieces</h2>${detailsSection()}
<h2>2. Your pieces in your looks</h2>
<p class="muted">Outlined in ink: in your answer key. Outlined in terracotta: not in it.</p>${looksSection()}
<h2>3. Inspirations</h2>${inspirationsSection()}
<h2>4. Stores</h2>${storesSection()}
<h2>5. Your year</h2>${yearSection()}
</body>
</html>
`;
}

function main() {
  const file = path.join(RESULTS_DIR, 'review.html');
  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  fs.writeFileSync(file, page());
  console.log(`Review page: server/spike/results/review.html`);
  if (!process.argv.includes('--no-open')) execFileSync('open', [file]);
}

main();
