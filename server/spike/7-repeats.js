// npm run spike:repeats
// Test 7 (T14): does Caro notice a piece that is already in the edit?
//
// The 16 piece photos from T1 go into a throwaway database as a member's edit. Then:
// - Made-up repeats: a second photo of each of the 16 is made here (darker, warmer or cooler,
//   turned and leaned a little, cropped). It should be found when its piece is in the edit, and
//   nothing should be flagged when its piece is taken out.
// - Marta's own photos, when they are there, in name order, two by two:
//   spike/photos/repeats/same/   1 and 2 are the same piece, 3 and 4 the next
//   spike/photos/repeats/alike/  1 and 2 only look alike, 3 and 4 the next
//   The first of each two goes into the edit, the second is the new piece.
//
// Pieces are cut out on this Mac with the same Apple feature as on the iPhone, so the background
// does not give the answer away. Choosing, question and answer form are the server's own
// (src/lib/lookalikes.js), and so is the reading of the details.
//
// Options:
//   --model sonnet,haiku   only these models for the comparing (default: both)
//   --effort low           think less or more (default low)
//   --only made            only the made-up repeats (or: own, only Marta's photos)

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const sharp = require('sharp');

// The real server code, on a throwaway database. Set before the database is loaded.
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'caro-repeats-'));
process.env.DATA_DIR = dataDir;
const db = require('../src/db');
const pieceDetails = require('../src/lib/piece-details');
const lookalikes = require('../src/lib/lookalikes');
const lookPhoto = require('../src/lib/look-photo');
const { now, iso } = require('../src/lib/today');

const { ask, pickModels, describeError, MODELS } = require('./lib/claude');
const { listPhotos, prepare } = require('./lib/images');
const { RESULTS_DIR, ensureDir, loadJson, saveJson, readOptions, dollars } = require('./lib/output');
const { loadWardrobe } = require('./lib/wardrobe');

const FULL = 2000;
const CUTOUTS = path.join(RESULTS_DIR, 'cutouts');

// --- Pictures ---

// Cuts out many photos at once (starting Swift takes a moment). Keeps what it made before.
function cutOut(photos) {
  ensureDir(CUTOUTS);
  const todo = photos.filter((p) => !fs.existsSync(p.cutout) && !fs.existsSync(p.cutout + '.none'));
  if (todo.length) {
    const args = todo.flatMap((p) => [p.path, p.cutout]);
    const lines = execFileSync('swift', [path.join(__dirname, 'lib', 'cutout.swift'), ...args], { encoding: 'utf8' }).trim().split('\n');
    todo.forEach((p, i) => lines[i] !== 'lifted' && fs.writeFileSync(p.cutout + '.none', ''));
  }
  for (const p of photos) p.lifted = fs.existsSync(p.cutout);
}

// The made-up second photos: another light, a little turned, leaned and cropped.
const LIGHTS = [
  { name: 'dim and warm', channels: [1.06, 0.95, 0.78], brightness: 0.72, saturation: 1.05 },
  { name: 'bright and cool', channels: [0.92, 1.0, 1.12], brightness: 1.16, saturation: 0.9 },
  { name: 'grey evening', channels: [0.97, 0.98, 1.04], brightness: 0.6, saturation: 0.65 },
  { name: 'yellow lamp', channels: [1.1, 1.0, 0.7], brightness: 0.9, saturation: 1.1 },
];

async function secondPhoto(photo, index) {
  const light = LIGHTS[index % LIGHTS.length];
  const dir = path.join(RESULTS_DIR, 'repeats-made');
  ensureDir(dir);
  const out = path.join(dir, photo.file + '.jpg');
  if (!fs.existsSync(out)) {
    const background = '#cfc8bd';
    const turned = await sharp(photo.path).rotate(index % 2 ? 11 : -9, { background }).toBuffer();
    const leaned = await sharp(turned).affine([1, index % 2 ? 0.07 : -0.06, index % 3 ? 0.03 : -0.03, 0.94], { background }).toBuffer();
    const meta = await sharp(leaned).metadata();
    const cut = 0.06;
    await sharp(leaned)
      .extract({
        left: Math.round(meta.width * cut),
        top: Math.round(meta.height * cut),
        width: Math.round(meta.width * (1 - 2 * cut)),
        height: Math.round(meta.height * (1 - 2 * cut)),
      })
      .modulate({ brightness: light.brightness, saturation: light.saturation })
      .linear(light.channels, [0, 0, 0])
      .jpeg({ quality: 85 })
      .toFile(out);
  }
  return { file: photo.file, path: out, light: light.name, cutout: path.join(CUTOUTS, `made-${photo.file}.png`) };
}

// --- The throwaway edit ---

const at = iso(now());
const userId = Number(
  db.prepare(`INSERT INTO users (email, name, status, onboarding_step, created_at) VALUES ('spike@example.test', 'Spike', 'active', 6, ?)`).run(at).lastInsertRowid
);

function addPiece(photo, details, status) {
  const name = `${userId}-${Math.random().toString(16).slice(2)}`;
  const folder = path.join('photos', String(userId));
  fs.mkdirSync(path.join(dataDir, folder), { recursive: true });
  const original = path.join(folder, `${name}-photo.jpg`);
  fs.copyFileSync(photo.path, path.join(dataDir, original));
  let cutout = null;
  if (photo.lifted) {
    cutout = path.join(folder, `${name}-cutout.png`);
    fs.copyFileSync(photo.cutout, path.join(dataDir, cutout));
  }
  const id = Number(
    db
      .prepare(
        `INSERT INTO pieces (user_id, status, details_status, name, kind, pattern, material, original_path, cutout_path, thumb_path, created_at)
         VALUES (?, ?, 'suggested', ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(userId, status, details.name, details.kind, details.pattern, details.material, original, cutout, cutout ?? original, at).lastInsertRowid
  );
  (details.colours || []).forEach((colour, i) =>
    db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, ?)').run(userId, id, colour, i + 1)
  );
  return id;
}

const removePiece = (id) => db.prepare('DELETE FROM pieces WHERE id = ?').run(id);
const chapterOf = (kind) => db.prepare('SELECT chapter FROM kinds WHERE name = ?').pluck().get(kind);

// Claude reads the details as it does for a new piece. Kept, so a second run does not pay again.
const saved = loadJson('repeats-details.json', {});
async function readDetails(key, file) {
  if (!saved[key]) {
    const photo = await sharp(file).rotate().resize({ width: 1568, height: 1568, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer();
    saved[key] = pieceDetails.checked(await pieceDetails.remote.claude(photo.toString('base64')));
    saveJson('repeats-details.json', saved);
  }
  return saved[key];
}

// --- Asking ---

// One question, as the server asks it. `without` leaves one piece out of the edit.
async function compare(pieceId, { model, effort, without = null }) {
  const piece = db.prepare('SELECT * FROM pieces WHERE id = ?').get(pieceId);
  const others = lookalikes.candidatesFor(piece).filter((other) => other.id !== without);
  if (others.length === 0) return { flags: [], asked: 0, cost: 0, seconds: 0 };
  const wardrobe = others.map((other, i) => ({ number: String(i + 1), piece: other }));
  const numbers = wardrobe.map((entry) => entry.number);
  const picture = await lookPhoto.pieceForClaude(piece, lookalikes.NEW_SIZE);
  const answer = await ask({
    test: '7-repeats',
    action: 'already in the edit',
    model,
    effort,
    system: lookalikes.SYSTEM,
    content: await lookalikes.promptFor(wardrobe, picture),
    schema: lookalikes.schemaFor(numbers),
    note: `${others.length} pieces`,
  });
  const flags = lookalikes.checked(answer.data, numbers).map(({ number, certainty }) => ({ id: others[Number(number) - 1].id, certainty }));
  return { flags, asked: others.length, cost: answer.cost, seconds: answer.seconds };
}

// A few at a time, as the server's own queue does.
async function inTurns(items, run) {
  const results = [];
  for (let i = 0; i < items.length; i += 3) results.push(...(await Promise.all(items.slice(i, i + 3).map(run))));
  return results;
}

async function score(title, cases, { model, effort }) {
  const rows = await inTurns(cases, async (c) => {
    try {
      const answer = await compare(c.newId, { model, effort, without: c.without });
      const named = answer.flags.map((flag) => `${db.prepare('SELECT name FROM pieces WHERE id = ?').pluck().get(flag.id)} (${flag.certainty})`);
      const found = c.expected ? answer.flags.some((flag) => flag.id === c.expected) : answer.flags.length === 0;
      const wrong = answer.flags.filter((flag) => flag.id !== c.expected).length;
      return { label: c.label, found, wrong, named, asked: answer.asked, cost: answer.cost, seconds: answer.seconds, inLine: c.inLine };
    } catch (error) {
      return { label: c.label, failed: describeError(error), cost: 0, seconds: 0 };
    }
  });
  const done = rows.filter((r) => !r.failed);
  const asked = done.filter((r) => r.asked > 0);
  const right = done.filter((r) => r.found && r.wrong === 0).length;
  console.log(`\n${title}, ${MODELS[model].label}: ${right} of ${rows.length} right`);
  for (const r of rows) {
    if (r.failed) console.log(`  FAILED  ${r.label}: ${r.failed}`);
    else if (!r.found || r.wrong) console.log(`  WRONG   ${r.label}: ${r.named.join(', ') || 'nothing flagged'}${r.inLine === false ? ' (its piece was not compared: read as another chapter)' : ''}`);
  }
  if (asked.length) {
    const average = (key) => asked.reduce((sum, r) => sum + r[key], 0) / asked.length;
    console.log(`  ${asked.length} questions, on average ${average('asked').toFixed(1)} pieces compared, ${average('seconds').toFixed(1)} s, ${dollars(average('cost'))} each`);
  }
  return rows;
}

// --- The run ---

async function main() {
  const options = readOptions();
  const models = pickModels(options.model || 'sonnet,haiku');
  const effort = options.effort || 'low';
  const results = {};

  // The 16 pieces, with the details from test 1 and Marta's corrections, as her edit.
  const wardrobe = await loadWardrobe();
  const originals = [];
  for (const photo of listPhotos('pieces')) {
    const copy = await prepare(photo, FULL);
    originals.push({ file: photo.file, path: copy.path, cutout: path.join(CUTOUTS, `piece-${photo.file}.png`) });
  }
  const made = [];
  for (const [i, photo] of originals.entries()) made.push(await secondPhoto(photo, i));

  const own = { same: [], alike: [] };
  for (const kind of Object.keys(own)) {
    for (const photo of listPhotos(path.join('repeats', kind))) {
      const copy = await prepare(photo, FULL);
      own[kind].push({ file: photo.file, path: copy.path, cutout: path.join(CUTOUTS, `${kind}-${photo.file}.png`) });
    }
    if (own[kind].length % 2) console.log(`spike/photos/repeats/${kind}/ has an odd number of photos; the last one is left out.`);
  }
  const ownCount = own.same.length + own.alike.length;
  console.log(ownCount ? `Marta's own photos: ${own.same.length} in same/, ${own.alike.length} in alike/` : "Marta's own photos: not there yet.");

  cutOut([...originals, ...made, ...own.same, ...own.alike]);
  const lifted = [...originals, ...made].filter((p) => p.lifted).length;
  console.log(`Cut out on this Mac: ${lifted} of ${originals.length + made.length}`);

  const inEdit = originals.map((photo) => addPiece(photo, wardrobe.find((w) => w.file === photo.file).details, 'confirmed'));

  // Marta's pairs: the first of each two goes into the edit too.
  const ownCases = [];
  for (const kind of Object.keys(own)) {
    for (let i = 0; i + 1 < own[kind].length; i += 2) {
      const [first, second] = [own[kind][i], own[kind][i + 1]];
      const firstDetails = await readDetails(`${kind}/${first.file}`, first.path);
      const secondDetails = await readDetails(`${kind}/${second.file}`, second.path);
      ownCases.push({ kind, first, second, secondDetails, firstId: addPiece(first, firstDetails, 'confirmed'), label: `${firstDetails.name} / ${secondDetails.name}` });
    }
  }

  if (options.only !== 'own') {
    const cases = await inTurns([...made.entries()], async ([i, photo]) => {
      const details = await readDetails(`made/${photo.file}`, photo.path);
      return { i, photo, details };
    });
    const before = cases.map(({ i, photo, details }) => {
      const original = wardrobe.find((w) => w.file === photo.file).details;
      return { i, label: `${original.name} (${photo.light}, read as ${details.name})`, inLine: chapterOf(details.kind) === chapterOf(original.kind), photo, details };
    });
    for (const model of models) {
      results[model] = results[model] || {};
      const withNew = before.map((c) => ({ ...c, newId: addPiece(c.photo, c.details, 'pending'), expected: inEdit[c.i] }));
      // Each new piece is compared with the edit only, not with the other new ones.
      hideOthers(withNew);
      results[model].madeSame = await score('Made-up repeats, its piece in the edit', withNew, { model, effort });
      results[model].madeNone = await score('Made-up repeats, its piece taken out', withNew.map((c) => ({ ...c, expected: null, without: inEdit[c.i] })), { model, effort });
      withNew.forEach((c) => removePiece(c.newId));
    }
  }

  if (ownCases.length && options.only !== 'made') {
    for (const model of models) {
      results[model] = results[model] || {};
      const withNew = ownCases.map((c) => ({
        ...c,
        newId: addPiece(c.second, c.secondDetails, 'pending'),
        expected: c.kind === 'same' ? c.firstId : null,
        inLine: c.kind === 'same' ? chapterOf(c.secondDetails.kind) === chapterOf(db.prepare('SELECT kind FROM pieces WHERE id = ?').pluck().get(c.firstId)) : undefined,
      }));
      hideOthers(withNew);
      for (const kind of Object.keys(own)) {
        const title = kind === 'same' ? "Marta's photos, the same piece twice" : "Marta's photos, two pieces that look alike";
        results[model][kind] = await score(title, withNew.filter((c) => c.kind === kind), { model, effort });
      }
      withNew.forEach((c) => removePiece(c.newId));
    }
  }

  saveJson(`repeats-${effort}.json`, results);
  console.log(`\nSaved to server/spike/results/repeats-${effort}.json`);
}

// Marks the new pieces as already asked about with each other, so only the edit is compared.
function hideOthers(cases) {
  const add = db.prepare(
    `INSERT OR IGNORE INTO piece_lookalikes (user_id, piece_id, other_id, certainty, answer, created_at) VALUES (?, ?, ?, 'high', 'different', ?)`
  );
  for (const a of cases) for (const b of cases) if (a.newId < b.newId) add.run(userId, b.newId, a.newId, at);
}

main()
  .catch((error) => console.error(describeError(error)))
  .finally(() => {
    db.close();
    fs.rmSync(dataDir, { recursive: true, force: true });
  });
