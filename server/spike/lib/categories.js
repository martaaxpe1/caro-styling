// The one list of categories the spike proposes for the PRD (open question 4 from T0).
// Every kind belongs to one chapter (how the edit groups pieces) and one slot
// (where it goes on the styling table). The role says what it counts as for the unlock rule.
//
// Open points to agree with Marta, marked "open" below:
// - knitwear on the styling table: a jumper is a top, but a cardigan is often worn as a layer.
// - belts, scarves, hats and jewellery all share the accessories slot.

const CHAPTERS = [
  'outerwear',
  'knitwear',
  'shirts and tops',
  'trousers and skirts',
  'dresses',
  'shoes',
  'bags and accessories',
];

// kind: [chapter, slot, role for the unlock rule]
const KINDS = {
  coat: ['outerwear', 'outer layer', null],
  'trench coat': ['outerwear', 'outer layer', null],
  'puffer jacket': ['outerwear', 'outer layer', null],
  jacket: ['outerwear', 'outer layer', null],
  'leather jacket': ['outerwear', 'outer layer', null],
  'denim jacket': ['outerwear', 'outer layer', null],
  blazer: ['outerwear', 'outer layer', null],
  gilet: ['outerwear', 'outer layer', null],

  jumper: ['knitwear', 'top', 'top'],
  cardigan: ['knitwear', 'top', 'top'], // open: or outer layer
  'knitted vest': ['knitwear', 'top', 'top'],
  'knitted top': ['knitwear', 'top', 'top'],

  shirt: ['shirts and tops', 'top', 'top'],
  blouse: ['shirts and tops', 'top', 'top'],
  't-shirt': ['shirts and tops', 'top', 'top'],
  'long-sleeved top': ['shirts and tops', 'top', 'top'],
  'tank top': ['shirts and tops', 'top', 'top'],
  bodysuit: ['shirts and tops', 'top', 'top'],
  sweatshirt: ['shirts and tops', 'top', 'top'],

  trousers: ['trousers and skirts', 'bottom', 'bottom'],
  jeans: ['trousers and skirts', 'bottom', 'bottom'],
  shorts: ['trousers and skirts', 'bottom', 'bottom'],
  skirt: ['trousers and skirts', 'bottom', 'bottom'],

  dress: ['dresses', 'top and bottom', 'one-piece'],
  jumpsuit: ['dresses', 'top and bottom', 'one-piece'],

  trainers: ['shoes', 'shoes', 'shoes'],
  boots: ['shoes', 'shoes', 'shoes'],
  'ankle boots': ['shoes', 'shoes', 'shoes'],
  loafers: ['shoes', 'shoes', 'shoes'],
  'ballet flats': ['shoes', 'shoes', 'shoes'],
  heels: ['shoes', 'shoes', 'shoes'],
  sandals: ['shoes', 'shoes', 'shoes'],
  mules: ['shoes', 'shoes', 'shoes'],

  bag: ['bags and accessories', 'bag', null],
  belt: ['bags and accessories', 'accessories', null], // open
  scarf: ['bags and accessories', 'accessories', null], // open
  hat: ['bags and accessories', 'accessories', null],
  sunglasses: ['bags and accessories', 'accessories', null],
  jewellery: ['bags and accessories', 'accessories', null],
};

const COLOURS = [
  'black',
  'white',
  'cream',
  'beige',
  'camel',
  'brown',
  'grey',
  'navy',
  'blue',
  'light blue',
  'green',
  'olive',
  'red',
  'burgundy',
  'pink',
  'terracotta',
  'orange',
  'yellow',
  'purple',
  'silver',
  'gold',
];

const PATTERNS = ['plain', 'striped', 'checked', 'floral', 'polka dot', 'animal print', 'graphic', 'other pattern'];

const MATERIALS = [
  'cotton',
  'linen',
  'wool',
  'cashmere',
  'silk',
  'satin',
  'denim',
  'leather',
  'suede',
  'faux leather',
  'viscose',
  'polyester',
  'nylon',
  'canvas',
  'straw',
  'metal',
  'not sure',
];

const WARMTH = ['light', 'medium', 'warm'];

const FORMALITY = ['casual', 'smart casual', 'smart', 'formal'];

// The list as text, for prompts: "outerwear: coat, trench coat, ..."
function kindsByChapterText() {
  return CHAPTERS.map((chapter) => {
    const kinds = Object.keys(KINDS).filter((kind) => KINDS[kind][0] === chapter);
    return `- ${chapter}: ${kinds.join(', ')}`;
  }).join('\n');
}

// True when the model picked a kind that belongs to the chapter it picked.
function kindMatchesChapter(kind, chapter) {
  return Boolean(KINDS[kind]) && KINDS[kind][0] === chapter;
}

module.exports = {
  CHAPTERS,
  KINDS,
  KIND_NAMES: Object.keys(KINDS),
  COLOURS,
  PATTERNS,
  MATERIALS,
  WARMTH,
  FORMALITY,
  kindsByChapterText,
  kindMatchesChapter,
};
