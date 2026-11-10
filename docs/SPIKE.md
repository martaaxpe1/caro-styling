# T1 AI spike: results

10 November 2026. Branch `t1-ai-spike`. The scripts are in `server/spike/`, and its README says how to run them.

The spike tested how well Claude recognises Marta's clothes, what each action costs, and which model to use, on her own photos: 16 pieces, 5 looks and 5 inspirations. It compared three models: Opus 5.5 (largest), Sonnet 5.5 (half the price of Opus) and Haiku 5.5 (about a fortieth of Opus). All prices are Anthropic's list prices, checked on 10 November 2026.

The whole spike cost $4.26 over 288 calls. Every call finished normally: no model declined a request, and no answer contained styling advice.

## In short

- **Sonnet 5.5 for everything that looks at photos.** It gave the best piece details (Marta's review), found every piece in her looks, and costs half as much as Opus for the same quality.
- **Haiku 5.5 for everything that searches the web.** It searched before answering, where the larger models often answered from memory and got some addresses wrong. It costs a few cents at most.
- **Your year: a simple rule in code proposes the seasons.** It was right in all six places, costs nothing, and its answer never changes. The typical highs shown to the member come from Sonnet's memory, which was closer to the official numbers than either free data source.
- **Store search needs two changes:** search the store's whole website rather than a country page, and open each product page to get its image and check the link still works.
- **Still to do:** test 6, the iPhone cut-outs, by hand (see below).

## Recommended model per action

| Action | Model | Settings | Cost per action |
|---|---|---|---|
| Details for a new piece | Sonnet 5.5 | photo at 1568 px, effort low | $0.010, so $1 for a first wardrobe of 100 pieces |
| Look from a photo | Sonnet 5.5 | wardrobe as small photos and details, effort medium | $0.021 at 16 pieces; about $0.10 at 100 pieces, $0.01 if another look follows within 5 minutes |
| Inspiration | Sonnet 5.5 | as above | $0.024 at 16 pieces; about $0.10 at 100 pieces |
| Store website for a country | Haiku 5.5 | web search | $0.018 |
| Search a store for one piece | Haiku 5.5 | web search, then web fetch for each product page | about $0.035 for up to five products |
| Your year | Sonnet 5.5 for the typical weather, no AI for the seasons | effort low | $0.006 per city, once |

**Effort** is how much a model thinks before answering. Low was enough for piece details. Medium was used for looks and inspirations, and the spike did not try other levels there.

**The cache.** For a look or an inspiration, most of the request is the wardrobe, and it is the same every time. Claude keeps it for 5 minutes and reads it again at a tenth of the price. So adding several looks in a row is cheap, but a single look on its own pays full price.

## Test 1: details for each piece

Each of the 16 piece photos went to each model, which filled in a fixed form: name, chapter and kind, colours, pattern, material, warmth and formality. Marta reviewed the answers on the review page. She chose Sonnet's as the best and corrected one colour: piece 01, pink ballet flats, is pink only. The models had added the black insole.

Each model scored against Marta's reviewed answers. These are Sonnet's answers with her correction, so Sonnet scores full marks by definition.

| Model | Kind and chapter | Colours | Material | Warmth | Formality | Cost per piece | Time |
|---|---|---|---|---|---|---|---|
| Sonnet, 1568 px | 16 of 16 | 16 | 16 | 16 | 16 | $0.0098 | 2 s |
| Opus, 1568 px | 16 | 15 | 16 | 14 | 13 | $0.020 | 3 s |
| Haiku, 1568 px | 16 | 12 | 13 | 11 | 10 | $0.0005 | 1.5 s |
| Sonnet, 1024 px | 16 | 11 | 15 | 15 | 15 | $0.0072 | 2 s |

What works:
- Every model got the kind and chapter right for every piece, from the one list of categories (below).
- Sonnet and Opus give good, short names, like "Washed black barrel jeans" or "Cream striped jumper".

What does not:
- **Colour is the weak point.** Haiku called the pale pink t-shirt white, cream or light blue, and the green striped shirt navy. It also often says "not sure" for material.
- **Smaller photos hurt colour.** At 1024 px, Sonnet made the same colour mistakes as Haiku. Keep 1568 px. The saving at 1024 px is a quarter of a cent per piece.
- **Warmth and formality are judgement calls.** The models disagree on them more than on anything else, so the member should check them.

Two prompt fixes came out of the review:
- A pair of shoes counts as one piece. At first, Sonnet and Haiku flagged both pairs as "more than one piece".
- Colours are only those seen from the outside when the piece is worn: no linings, insoles, soles or labels. After this fix, all three models give piece 01 as pink only.

## Test 2: your pieces in a photo of you

Each model got the wardrobe (a small photo and the details of each of the 16 pieces) and a photo of Marta wearing a look. It said which pieces she is wearing and how sure it is, and listed what she wears that is not in the wardrobe. Answers were scored against Marta's own list for each look.

| Model | Wardrobe sent as | Found | Wrongly added |
|---|---|---|---|
| Opus | photos and details | 7 of 7 | 0 |
| Sonnet | photos and details | 7 of 7 | 1, marked low certainty |
| Haiku | photos and details | 7 of 7 | 0 |
| All three | details only, no photos | 7 of 7 | 0 |

What works:
- Every model found every piece, almost always with high certainty.
- They describe what is not in the wardrobe well, such as "Black fitted leggings", "White ankle boots" and "White crew-neck t-shirt worn under the shirt". Those could become new pieces to add.

What to keep in mind:
- **This test was easy.** Each look had one or two of the 16 pieces, and the pieces are quite different from each other. A real wardrobe of 100 pieces with three black jumpers will be harder, and that is where the wardrobe photos matter. Test again in T9 with Marta's real wardrobe.
- **Low certainty should be a question.** Sonnet's one wrong piece was marked low. The app can show low-certainty pieces as "Is this your pale pink t-shirt?" instead of ticking them.
- **Cost grows with the wardrobe.** Each piece adds about 380 tokens (its small photo and its line of details). At 100 pieces, a look costs about $0.10 on Sonnet. Smaller wardrobe photos would cut this, worth trying in T9.

## Test 3: inspirations

Each model described every piece in an inspiration and picked Marta's closest piece of the same kind, marked yours, close or missing.

What works:
- **The three models agree** on almost every piece and every match, across all five inspirations.
- **The descriptions are good,** like "Navy quilted mandarin-collar jacket", "Pink suede ballet flats with bow" or "Black leather belt with silver buckle".
- **Yours is used sparingly.** Opus and Sonnet marked only one piece as yours: the cream wide-leg trousers (08) in inspiration 3. That is right. Haiku also marked the striped jumper (06) in inspiration 5 as yours, where the others said close.

What changed:
- **"Close" was generous.** The first prompt followed the PRD: close meant the same kind, but different in colour, shape or material. So a grey chunky jumper was close to Marta's black jumper, black Mary Janes to her pink ballet flats, and black canvas trainers to her grey running trainers.
- **Marta chose a stricter close** (proposal 5): the same kind and a similar colour. Rerun on Sonnet, the grey jumper, the Mary Janes, the trainers, the camel trousers and the blue jeans all became missing, each with Marta's nearest piece of that kind. A black skirt, black jeans and the pink suede ballet flats stayed close.
- **One inconsistency:** a black crossbody bag was missing in inspiration 2 (a structured leather bag) but close in inspiration 5 (a small one), against the same black beaded handbag. Watch for this in T10.

## Test 4: stores

### Finding each store's website

Each model found the online shop of Marta's seven stores, for the Netherlands and for the US. The addresses were then opened with a plain request, no AI, to check that they work.

| Store | The Netherlands | The US |
|---|---|---|
| Zara | all three right | all three right |
| Bimba y Lola | all three work | all three right |
| Samsøe Samsøe | all three work | all three right |
| Ganni | Opus and Sonnet wrong (page not found), Haiku right | Sonnet wrong, Opus and Haiku right |
| COS, Arket, Uniqlo | cannot be checked: the sites refuse plain requests | same |
| Arket in the US | | all three: no online shop in the US |

What works: Haiku searched for every store and was right wherever the address could be checked. $0.018 per store per country.

What does not: Opus and Sonnet usually answered from memory without searching, and some of those addresses do not exist. The instructions should require a search.

### Searching a store for one piece

The piece was a black long wool coat, the first missing piece in inspiration 2. It was searched for at COS, with Claude's web search limited to COS's website.

- **In the US,** all three models found the same five black wool long coats, with names, prices in dollars and links. Two of the five are men's coats. Haiku cost $0.012; Opus and Sonnet cost $0.09 to $0.14.
- **In the Netherlands,** searching only `cos.com/nl-nl` (the address Opus and Sonnet gave) found nothing, on all three models, even when asked to search in Dutch. Searching the whole of `cos.com` from the Netherlands found three coats in euros, on COS's Dutch shop at `cos.com/en-nl`. $0.023 on Haiku.
- **Product images:** the search results never include one, and COS refuses plain requests for its product pages. Claude's own web fetch can open them: it found the main image on Sonnet for $0.053 and on Haiku for $0.0019. The image itself then opens with a plain request, so the app can show it.
- **Out-of-date links:** one product link from the search no longer opened. Opening each product page also catches that.

So the recommended way is:
1. Search the store's whole website, with the member's country set, using Haiku.
2. Keep only women's or unisex products in the member's currency. Marta chose women's or unisex after the first run.
3. Open each product page with Haiku's web fetch, to get its image and drop links that no longer work.

That is about $0.035 for up to five products.

## Test 5: your year

For each place, the spike compared the official typical weather (1991 to 2020, from KNMI, NOAA and Argentina's weather service) with two free data sources and with each model's memory. Three famous cities, then three smaller places, to see whether memory holds beyond famous places.

How far each source is from the official daily highs, on average over the 12 months:

| Place | Open-Meteo | NASA POWER | Opus | Sonnet | Haiku |
|---|---|---|---|---|---|
| Amsterdam | 1.1 °C | 1.2 °C | 0.3 °C | 0.1 °C | 0.4 °C |
| Miami | 2.0 | 2.5 | 0.2 | 0.2 | 0.5 |
| Buenos Aires | 2.3 | 2.5 | 0.3 | 0.2 | 1.8 |
| Vlissingen | 0.5 | 0.4 | 0.3 | 0.4 | 0.6 |
| Vero Beach, Florida | 1.3 | 0.9 | 0.2 | 0.2 | 0.2 |
| Mar del Plata | 1.2 | 2.0 | 0.3 | 0.4 | 1.0 |

What this shows:
- **Opus and Sonnet remember typical weather very well,** within 0.4 °C everywhere, small places included.
- **The free data sources run cold,** by up to 2.5 °C. They average weather over a grid square, and these weather stations are on warm coasts or in cities. In Miami, Open-Meteo gives a July high of 86 °F where the official figure is 91 °F. Sara would notice.
- **Open-Meteo's free service is for non-commercial use,** and slows you down after large requests. The app would fetch each city once and keep it.

Proposing the seasons:
- **The rule in code proposed the PRD's years in all six places:** four seasons in Amsterdam, Vlissingen, Buenos Aires and Mar del Plata (reversed in the south), and two in Miami and Vero Beach (hot and rainy May to October, mild and dry November to April).
- **The models were less steady.** Sonnet matched the rule in five places of six. Opus moved Vlissingen's summer to June to September and Mar del Plata's to December to March. Haiku gave Vero Beach two seasons that overlap, which is not a valid year.
- **One naming difference:** Opus and Sonnet call Miami's November to April "warm and dry". Marta chose to keep "mild and dry", as in the PRD and the rule.

## Test 6: the iPhone's own cut-outs

Not done yet. Marta does it by hand on her iPhone, following `server/spike/6-cutouts.md`, and records good, fair, poor or failed for each of the 16 piece photos. The fallback recommendation will be added here afterwards. If the cut-outs are poor, the simplest fallback is to keep the photo as it is, on Caro's tile colour, and let the member retake it.

## What the AI costs a member

From the averages above, with the recommended models:

| A member's month | Cost |
|---|---|
| First wardrobe of 100 pieces | about $1 |
| A typical month after that: 20 new pieces, 15 looks from photos, 15 inspirations, 5 store searches | about $3 |
| Worst case: 300 looks from photos at 100 pieces each, none cached | about $30 |

The spike itself made 288 calls, close to a heavy month for one member.

## Agreed changes to the PRD

Agreed with Marta on 10 November and applied to `docs/PRD.md` as v1.1.

1. **Section 6, one list of categories.** This answers open question 4. There are seven chapters with short names. Inside each chapter, the kind is a filter on the Chapter screen (S6). Sweatshirts join knitwear, skirts join dresses, leggings join trousers. Cardigans are always a top.

   | # | Chapter | Kinds | Slot on the styling table |
   |---|---|---|---|
   | 01 | Outerwear | coat, trench coat, puffer jacket, jacket, leather jacket, denim jacket, blazer, gilet | outer layer |
   | 02 | Knitwear | jumper, cardigan, knitted vest, knitted top, sweatshirt, hoodie | top |
   | 03 | Tops | shirt, blouse, t-shirt, long-sleeved top, tank top, bodysuit | top |
   | 04 | Trousers | trousers, jeans, shorts, leggings | bottom |
   | 05 | Dresses and skirts | dress, jumpsuit; skirt | one-piece; bottom |
   | 06 | Shoes | trainers, boots, ankle boots, loafers, ballet flats, heels, sandals, mules | shoes |
   | 07 | Accessories | bag; belt, scarf, hat, sunglasses, jewellery | bag; accessories |

   Rerun on Sonnet, the hoodie, jeans, trousers, dress and both skirts all land in the new chapters.

   The chapter names change on three screens: The edit (10), The edit while still building (08), and the review (07), where "Category Bottoms · Skirt" becomes "Dresses and skirts · Skirt".

2. **Section 8, fixed lists for the details.**
   - Colours (21): black, white, cream, beige, camel, brown, grey, navy, blue, light blue, green, olive, red, burgundy, pink, terracotta, orange, yellow, purple, silver, gold.
   - Patterns: plain, striped, checked, floral, polka dot, animal print, graphic, other pattern.
   - Materials: cotton, linen, wool, cashmere, silk, satin, denim, leather, suede, faux leather, viscose, polyester, nylon, canvas, straw, metal, not sure.
   - Formality: casual, smart casual, smart, formal.
   - Colours are only those seen from the outside when the piece is worn.

3. **Section 8, looks from a photo.** Pieces spotted with low certainty are asked about, not ticked.

4. **Section 8, store search, and section 6, store.**
   - A store is saved as its website, such as cos.com, and searched as a whole with the member's country set.
   - Only women's or unisex products, and only results in the member's currency.
   - Each product page is opened to get its image and to drop links that no longer work.

   Rerun on Haiku with these rules, COS gave only women's coats: three in euros and five in dollars.

5. **Section 8, what close means.** This answers open question 8.
   - Close is the same kind and a similar colour.
   - Anything else is missing, with the member's nearest piece of that kind shown under it, like "Your nearest: black knit jumper".
   - Close does not count as yours.

6. **Sections 9 and 10, your year.**
   - Seasons are proposed by a rule in code, not by the AI:
     - Four seasons when the typical highs vary by 10 °C or more over the year.
     - Otherwise two, when most of the rain falls in six months in a row.
     - Otherwise none.
   - The typical highs and rain come from Sonnet's memory, checked against Open-Meteo. If they differ by more than 3 °C in any month, Open-Meteo's numbers are used.
   - Miami's November to April stays mild and dry.

7. **Section 10, the allowance.** Start at 300 AI actions a month per member. Each piece, look, inspiration or search counts as one action.

8. **Section 18, decided in T1.**
   - The model per action, from the table above.
   - The climate source, as in proposal 6.
   - The cut-out fallback, once test 6 is done.

## Prompts

The prompts are in the spike scripts and carry over to the server as they are:
- Details: `server/spike/1-details.js`.
- Looks and inspirations: `server/spike/lib/wardrobe.js`, `2-looks.js` and `3-inspirations.js`.
- Stores: `server/spike/4-stores.js`.
- Your year: `server/spike/5-year.js`.

Every prompt says the AI recognises and describes, and never suggests looks, says what goes with what, or judges style. Every answer is a fixed form with no free-text field for advice, apart from short descriptions of pieces.
