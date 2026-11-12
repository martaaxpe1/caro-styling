// npm run seed-wardrobe                     (Marta, from ADMIN_EMAIL in server/.env)
// npm run seed-wardrobe -- sara@example.com  (another member who finished set-up)
// npm run seed-wardrobe -- --open            (also 4 pairs of shoes: 23 pieces, Looks open; T7)
//
// For testing the unlock rule (PRD section 17, T5): replaces the member's pieces with 19
// confirmed ones, with tops and bottoms but no shoes, and locks Looks and Get the look again.
// Adding one pair of shoes then opens them.
//
// The pieces are drawn, not photographed: the clothing shapes from the design canvas
// (design/screens/06-adding-pieces.dc.html), turned into pictures by sharp. They go through
// the same steps as a real photo, so they look like cut-outs in the app. No AI, no cost.
//
// Only on this Mac. It deletes the member's pieces and photos, so it refuses to run online.

const db = require('../src/db');
const photos = require('../src/lib/photos');
const pieceSeasons = require('../src/lib/piece-seasons');
const { progress, checkUnlock } = require('../src/lib/wardrobe');
const { now, iso } = require('../src/lib/today');
const sharp = require('sharp');

if (process.env.NODE_ENV === 'production' || process.env.RENDER) {
  console.error('seed-wardrobe deletes pieces, so it only runs on your Mac, never online. Nothing was changed.');
  process.exit(1);
}

// The shapes, drawn on a square of 100 by 100, from the design canvas.
const SHAPES = {
  tee: 'M32 14 L43 10 Q50 17 57 10 L68 14 L84 28 L75 38 L68 33 L68 88 L32 88 L32 33 L25 38 L16 28 Z',
  shirt: 'M33 12 L44 8 L50 16 L56 8 L67 12 L84 62 L75 65 L67 38 L67 90 L33 90 L33 38 L25 65 L16 62 Z',
  knit: 'M32 13 L42 9 Q50 15 58 9 L68 13 L86 64 L76 67 L68 40 L68 88 L32 88 L32 40 L24 67 L14 64 Z',
  vest: 'M34 12 L43 10 Q50 26 57 10 L66 12 L70 32 L68 88 L32 88 L30 32 Z',
  coat: 'M33 8 L44 5 L50 22 L56 5 L67 8 L82 60 L74 62 L69 42 L71 95 L29 95 L31 42 L26 62 L18 60 Z',
  blazer: 'M33 10 L44 7 L50 26 L56 7 L67 10 L82 58 L74 60 L69 40 L70 80 L30 80 L31 40 L26 60 L18 58 Z',
  trousers: 'M31 8 L69 8 L73 94 L56 94 L50 34 L44 94 L27 94 Z',
  leggings: 'M36 8 L64 8 L66 94 L55 94 L50 34 L45 94 L34 94 Z',
  skirt: 'M36 14 L64 14 L78 88 L22 88 Z',
  dress: 'M39 6 L44 6 Q50 13 56 6 L61 6 L63 32 L76 92 L24 92 L37 32 Z',
  jumpsuit: 'M39 6 L44 6 Q50 13 56 6 L61 6 L63 40 L68 94 L54 94 L50 50 L46 94 L32 94 L37 40 Z',
  shoe: 'M12 52 Q13 40 28 40 L52 42 Q68 44 84 51 Q91 54 89 60 L14 60 Q10 58 12 52 Z',
  boot: 'M30 14 L52 14 L54 58 Q70 60 84 66 Q90 69 88 76 L24 76 Q22 70 26 62 Z',
  bag: 'M24 42 L76 42 L80 86 L20 86 Z M36 42 Q36 18 50 18 Q64 18 64 42 L60 42 Q60 23 50 23 Q40 23 40 42 Z',
};

// A pale piece gets a thin outline, as in the design, so it shows on the paper colour.
const OUTLINE = '#CFC6B8';

// [name, kind, shape, fill, colours, pattern, material, warmth, formality, occasion]
const PIECES = [
  ['Camel wool coat', 'coat', 'coat', '#B88A5E', ['camel'], 'plain', 'wool', 'warm', 'smart', 'Office'],
  ['Brown wool blazer', 'blazer', 'blazer', '#5A4033', ['brown'], 'plain', 'wool', 'medium', 'smart', 'Office'],
  ['Blue denim jacket', 'denim jacket', 'blazer', '#4A5E7E', ['blue'], 'plain', 'denim', 'medium', 'casual', 'Day out'],
  ['Grey wool jumper', 'jumper', 'knit', '#A9A8A3', ['grey'], 'plain', 'wool', 'warm', 'smart casual', 'Working from home'],
  ['Oatmeal cardigan', 'cardigan', 'knit', '#D8C7A8', ['beige'], 'plain', 'wool', 'medium', 'smart casual', 'Office'],
  ['Navy sweatshirt', 'sweatshirt', 'knit', '#2E3A55', ['navy'], 'plain', 'cotton', 'medium', 'casual', 'Working from home'],
  ['Cream knitted vest', 'knitted vest', 'vest', '#EDE3CF', ['cream'], 'plain', 'wool', 'medium', 'smart casual', 'Day out'],
  ['White cotton shirt', 'shirt', 'shirt', '#FBF9F4', ['white'], 'plain', 'cotton', 'light', 'smart casual', 'Office'],
  ['Cream t-shirt', 't-shirt', 'tee', '#F6F0E4', ['cream'], 'plain', 'cotton', 'light', 'casual', 'Day out'],
  ['Light blue blouse', 'blouse', 'shirt', '#B9CCE0', ['light blue'], 'plain', 'viscose', 'light', 'smart', 'Office'],
  ['Navy long-sleeved top', 'long-sleeved top', 'knit', '#3D4A66', ['navy', 'white'], 'striped', 'cotton', 'medium', 'casual', 'Day out'],
  ['Black tank top', 'tank top', 'vest', '#22211F', ['black'], 'plain', 'cotton', 'light', 'casual', 'Night out'],
  ['Navy wool trousers', 'trousers', 'trousers', '#2E3A55', ['navy'], 'plain', 'wool', 'medium', 'smart', 'Office'],
  ['Blue straight jeans', 'jeans', 'trousers', '#4A5E7E', ['blue'], 'plain', 'denim', 'medium', 'casual', 'Day out'],
  ['Black leggings', 'leggings', 'leggings', '#22211F', ['black'], 'plain', 'nylon', 'medium', 'casual', 'Working from home'],
  ['Terracotta linen skirt', 'skirt', 'skirt', '#B4765F', ['terracotta'], 'plain', 'linen', 'light', 'smart casual', 'Day out'],
  ['Black midi dress', 'dress', 'dress', '#22211F', ['black'], 'plain', 'viscose', 'medium', 'smart', 'Night out'],
  ['Olive jumpsuit', 'jumpsuit', 'jumpsuit', '#6B6B3A', ['olive'], 'plain', 'cotton', 'medium', 'casual', 'Day out'],
  ['Tan leather bag', 'bag', 'bag', '#A0703F', ['camel'], 'plain', 'leather', 'medium', 'smart casual', 'Office'],
];

// With --open: shoes, so the styling table has a choice and Looks open (T7).
const SHOES = [
  ['Black leather loafers', 'loafers', 'shoe', '#22211F', ['black'], 'plain', 'leather', 'medium', 'smart', 'Office'],
  ['Tan leather loafers', 'loafers', 'shoe', '#8A5A3C', ['camel'], 'plain', 'leather', 'medium', 'smart casual', 'Office'],
  ['Cream trainers', 'trainers', 'shoe', '#F3ECE0', ['cream'], 'plain', 'canvas', 'light', 'casual', 'Day out'],
  ['Brown suede ankle boots', 'ankle boots', 'boot', '#5A4033', ['brown'], 'plain', 'suede', 'warm', 'smart casual', 'Night out'],
];

// The cut-out (the shape on a transparent background) and a "photo" of it on the tile colour.
async function drawn(shape, fill) {
  const pale = ['#FBF9F4', '#F6F0E4', '#EDE3CF', '#F3ECE0'].includes(fill);
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="900" height="900" viewBox="0 0 100 100">` +
    `<path d="${SHAPES[shape]}" fill="${fill}" fill-rule="evenodd"${pale ? ` stroke="${OUTLINE}" stroke-width="1.2"` : ''}/></svg>`;
  const cutout = await sharp(Buffer.from(svg)).png().trim().toBuffer();
  const photo = await sharp(cutout)
    .extend({ top: 120, bottom: 120, left: 160, right: 160, background: '#EFE7DB' })
    .flatten({ background: '#EFE7DB' })
    .jpeg()
    .toBuffer();
  return { photo: photo.toString('base64'), cutout: cutout.toString('base64') };
}

const args = process.argv.slice(2);
const OPEN = args.includes('--open');

function findMember() {
  const email = (args.find((arg) => !arg.startsWith('--')) || process.env.ADMIN_EMAIL || '').trim().toLowerCase();
  if (!email.includes('@')) {
    console.error('Give an email, like npm run seed-wardrobe -- sara@example.com, or add ADMIN_EMAIL to server/.env.');
    process.exit(1);
  }
  const member = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
  if (!member) {
    console.error(`No member with the email ${email}. Nothing was changed.`);
    process.exit(1);
  }
  if (member.status !== 'active') {
    console.error(`${member.name} has not finished set-up (steps 1 to 5) yet. Nothing was changed.`);
    process.exit(1);
  }
  return member;
}

async function main() {
  const member = findMember();

  // Start from an empty wardrobe, with no looks, locked again (only here: online, unlocked
  // stays unlocked).
  db.prepare('DELETE FROM looks WHERE user_id = ?').run(member.id);
  db.prepare('UPDATE users SET looks_numbered = 0 WHERE id = ?').run(member.id);
  const old = db.prepare('SELECT * FROM pieces WHERE user_id = ?').all(member.id);
  db.prepare('DELETE FROM pieces WHERE user_id = ?').run(member.id);
  old.forEach((piece) => photos.removeFiles(photos.filesOf(piece)));
  db.prepare('UPDATE users SET unlocked_at = NULL WHERE id = ?').run(member.id);

  const occasions = new Map(
    db.prepare('SELECT id, name FROM occasions WHERE user_id = ?').all(member.id).map((o) => [o.name.toLowerCase(), o.id])
  );
  const rule = pieceSeasons.seasonsByWarmth(member.id);
  const add = db.prepare(
    `INSERT INTO pieces (user_id, status, details_status, name, kind, pattern, material, warmth, formality,
       original_path, cutout_path, thumb_path, created_at, confirmed_at)
     VALUES (?, 'confirmed', 'suggested', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const addColour = db.prepare('INSERT INTO piece_colours (user_id, piece_id, colour, position) VALUES (?, ?, ?, ?)');
  const addOccasion = db.prepare('INSERT INTO piece_occasions (user_id, piece_id, occasion_id) VALUES (?, ?, ?)');

  console.log(`\n${member.name}, ${member.email}`);
  const adding = OPEN ? [...PIECES, ...SHOES] : PIECES;
  console.log(`  Removed ${old.length} ${old.length === 1 ? 'piece' : 'pieces'} and any looks. Adding ${adding.length}:`);

  for (const [name, kind, shape, fill, colours, pattern, material, warmth, formality, occasion] of adding) {
    const files = await photos.savePiecePhotos(member.id, await drawn(shape, fill));
    const at = iso(now());
    const pieceId = Number(
      add.run(member.id, name, kind, pattern, material, warmth, formality, files.original, files.cutout, files.thumb, at, at).lastInsertRowid
    );
    colours.forEach((colour, index) => addColour.run(member.id, pieceId, colour, index + 1));
    pieceSeasons.proposeForPiece(member.id, pieceId, warmth, rule);
    if (occasions.has(occasion.toLowerCase())) addOccasion.run(member.id, pieceId, occasions.get(occasion.toLowerCase()));
    console.log(`  ${name} (${kind})`);
  }

  if (OPEN) checkUnlock(member.id);
  const p = progress(member.id);
  const check = (yes) => (yes ? 'yes' : 'no');
  console.log(`\n  ${p.pieces} of ${p.needed}. Top: ${check(p.top)}. Bottom or one-piece: ${check(p.bottomOrOnePiece)}. Shoes: ${check(p.shoes)}.`);
  console.log(`  Looks and Get the look: ${p.unlocked ? 'open' : 'locked. Add a pair of shoes to open them'}.`);
  if (rule.medium.length === 0) {
    console.log("  No seasons on these pieces: your city's typical weather is not known yet. It is looked up with your first photo.");
  }
  db.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
