// The one list of categories the spike proposes for the PRD (open question 4 from T0).
// Every kind belongs to one chapter (how the edit groups pieces) and one slot
// (where it goes on the styling table). The role says what it counts as for the unlock rule.
//
// Agreed with Marta on 10 November: seven short chapters, kinds as a filter inside each,
// cardigans always a top. Belts, scarves, hats and jewellery share the accessories slot.

// Sweatshirts join knitwear, skirts join dresses, leggings join trousers.
const CHAPTERS = ['outerwear', 'knitwear', 'tops', 'trousers', 'dresses and skirts', 'shoes', 'accessories'];

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
  cardigan: ['knitwear', 'top', 'top'],
  'knitted vest': ['knitwear', 'top', 'top'],
  'knitted top': ['knitwear', 'top', 'top'],
  sweatshirt: ['knitwear', 'top', 'top'],
  hoodie: ['knitwear', 'top', 'top'],

  shirt: ['tops', 'top', 'top'],
  blouse: ['tops', 'top', 'top'],
  't-shirt': ['tops', 'top', 'top'],
  'long-sleeved top': ['tops', 'top', 'top'],
  'tank top': ['tops', 'top', 'top'],
  bodysuit: ['tops', 'top', 'top'],

  trousers: ['trousers', 'bottom', 'bottom'],
  jeans: ['trousers', 'bottom', 'bottom'],
  shorts: ['trousers', 'bottom', 'bottom'],
  leggings: ['trousers', 'bottom', 'bottom'],

  dress: ['dresses and skirts', 'top and bottom', 'one-piece'],
  jumpsuit: ['dresses and skirts', 'top and bottom', 'one-piece'],
  skirt: ['dresses and skirts', 'bottom', 'bottom'],

  trainers: ['shoes', 'shoes', 'shoes'],
  boots: ['shoes', 'shoes', 'shoes'],
  'ankle boots': ['shoes', 'shoes', 'shoes'],
  loafers: ['shoes', 'shoes', 'shoes'],
  'ballet flats': ['shoes', 'shoes', 'shoes'],
  heels: ['shoes', 'shoes', 'shoes'],
  sandals: ['shoes', 'shoes', 'shoes'],
  mules: ['shoes', 'shoes', 'shoes'],

  bag: ['accessories', 'bag', null],
  belt: ['accessories', 'accessories', null],
  scarf: ['accessories', 'accessories', null],
  hat: ['accessories', 'accessories', null],
  sunglasses: ['accessories', 'accessories', null],
  jewellery: ['accessories', 'accessories', null],
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
