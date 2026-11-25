# The AI spike (T1)

Small scripts that test how well Claude recognises your clothes, what it costs, and which model to use, before we build screens on top of it. The findings go into `docs/SPIKE.md`.

## Before you start

1. **Your API key.** In `server/.env`, add a line `ANTHROPIC_API_KEY=` followed by your key from console.anthropic.com. Never paste it in chat or commit it. A monthly spend limit of about 25 dollars in the Console is plenty.
2. **Your photos.** Put them in these folders. HEIC, JPEG or PNG all work, so AirDrop from your iPhone is fine. Pieces are numbered 01 to 15 in name order.
   - `spike/photos/pieces/`: 15 photos, one piece each: flat or on a hanger, plain background, daylight. A mix of chapters, with at least two pairs of shoes and a bag. Choose pieces you wear in the looks.
   - `spike/photos/looks/`: 5 photos of you wearing looks, each with 3 to 5 of the 15 pieces. At least one piece that is not among the 15.
   - `spike/photos/inspirations/`: 5 images of looks you like. Some pieces close to yours, at least one you do not own.
   - `spike/photos/repeats/same/` (T14): 10 photos, five pieces photographed twice in different light. In name order, two by two: 1 and 2 are the same piece, 3 and 4 the next.
   - `spike/photos/repeats/alike/` (T14): 10 photos, five pairs of pieces that only look alike, like two black jumpers. Two by two in the same way.

The photos and everything made from them (in `spike/results/`) are ignored by Git. Copies sent to Claude are resized, turned upright and stripped of location data first.

## Running the tests

In Terminal, from the `server` folder. Each command prints what it found, with the time and cost of every call.

| Command | What it does |
|---|---|
| `npm run spike:check` | Checks the key and the photos. Costs nothing. |
| `npm run spike:details` | Test 1: details for each piece, from Opus, Sonnet and Haiku. |
| `npm run spike:review` | Opens a page with your photos next to the answers. Tell Claude what is wrong. |
| `npm run spike:looks` | Test 2: which pieces you wear in each look. Scored against your answer key. |
| `npm run spike:inspirations` | Test 3: the pieces in each inspiration, and your closest piece of the same kind. |
| `npm run spike:stores -- --piece "black leather loafers"` | Test 4: your stores' websites in the Netherlands and the US, then one piece searched in COS in each. |
| `npm run spike:year` | Test 5: typical weather for Amsterdam, Miami and Buenos Aires from two climate sources and from Claude, and a proposed year. |
| `npm run spike:repeats` | Test 7 (T14): a second photo of a piece that is already in the edit, made up from your 16 photos, and from your own pairs when they are there. |
| `npm run spike:costs` | The cost per action per model, and what 100 pieces would cost. |

Test 6, the iPhone's own cut-outs, is by hand: follow `spike/6-cutouts.md`.

Options, added after `--`, for example `npm run spike:details -- --model haiku --size 1024`:
- `--model opus,sonnet,haiku`: only some models
- `--size 1024`: smaller photos (test 1)
- `--text-only`: the wardrobe without its photos (tests 2 and 3)
- `--effort low|medium|high`: how much the model thinks before answering
- `--no-ai`: test 5 without Claude, free
- `--pieces 01,04`: test 1 for only these pieces; the answers for the others stay
- `--score`: test 2 scores the saved answers against your answer key again, free
- `--search-domain cos.com`: test 4 searches this whole website instead of the store's country page
- `--sections women,unisex`: test 4 searches only these store sections, any of women, men, unisex (default all three)
- `--local`: test 4 also searches in the country's language
- `--small-places`: test 5 for Vlissingen, Vero Beach and Mar del Plata, to check the models' memory beyond famous cities

Your corrections and answer key live in `spike/photos/answers.json`, next to your photos and also ignored by Git.

The findings are in `docs/SPIKE.md`.

## What it costs

Running everything once costs about 2 to 5 dollars. The whole spike, with reruns, stays under 15.
