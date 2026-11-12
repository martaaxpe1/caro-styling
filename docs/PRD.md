# Caro Styling: Product requirements (v1.5, ready to build)

The spec for building Caro Styling. It folds in every decision from the drafts (v0.2 to v0.10) and from the design round on the canvas. Where this file and the screens in `design/` disagree on layout, colour, type or copy, the screens win. Where they disagree on behaviour, this file wins. Changes are listed at the end.

---

## 1. Summary and value proposition

**Caro Styling is a styling studio for the clothes you already own.** You are the stylist. Caro gives you a calm, beautiful place to see your whole wardrobe, put looks together for your life, and turn the looks you love into versions made of your own pieces. It suggests buying only when a single key piece would complete a look you want, and only from the stores you choose.

How it works: you photograph the pieces you keep. Caro cuts them out and suggests their details. Looks come from three places, and you decide all of them:

1. **Built.** You put a look together on the styling table.
2. **From a photo.** You get dressed and take a photo. Caro spots which of your pieces you are wearing, you confirm, and it becomes a saved look with your photo.
3. **Inspired.** You add a look you like. Caro finds the closest piece you own for each part of it. If a missing piece is key to you, it searches your stores, in your country, for it.

What Caro is not: a daily outfit log, a timeline of what you wore, or an AI stylist.

### How it differs from what is out there

Most single features already exist (see `docs/BENCHMARK.md`). What is different is the stance, and the design shows it:

- **You style, the AI only sees.** The market is racing to be an AI stylist. Caro never proposes a look.
- **Shop your closet first.** An inspiration becomes your version before anything is bought. Buying is for one key piece at a time, in your own stores.
- **A studio, not a catalogue.** Your wardrobe reads like a magazine, under Sara Caro's brand, not like an inventory grid.

Invite only. Marta (Netherlands) and Sara (Miami) are the first two members and test it together, both on iPhone. Anyone invited, wherever they live, can onboard on their own.

## 2. Principles

- **The AI sees, you decide.** AI recognises things: it suggests details, spots your pieces in a photo, describes the pieces in an inspiration, and searches a store. It never decides what goes with what, never proposes looks, never judges your style.
- **Every recognition is a suggestion** you confirm or change.
- **Propose, then confirm.** Where you live, your seasons and your stores are proposed and checked with you.
- **Always your real photos.** No stock images of clothes you own.
- **Facts, not advice.** The wardrobe overview shows what you have, never what you should buy.
- **Narrow shopping.** Only when you ask, only for one piece, only in your stores.

## 3. Goals and non-goals

Goals:
- A real iPhone app, installed through TestFlight with its own icon.
- Accounts with a simple sign-in, and people added by the admin.
- An onboarding that works for anyone, anywhere, and ends with building the wardrobe.
- A wardrobe of cut-outs, quick to add in batches (about 100 pieces to start) and quick to confirm. Looks and Get the look open at 20 pieces.
- A wardrobe overview: what you have by category, colour, season and occasion, and which pieces are in no look yet.
- Looks from three sources (built, from a photo, inspired), each with occasions and seasons.
- Inspirations rebuilt with your pieces, missing pieces flagged.
- A targeted search for a missing key piece in your stores, for your country.
- A To find list (the wishlist), inside Get the look.

Non-goals for version one:
- A daily outfit log, a history or timeline, and statistics on what you wear.
- Look suggestions, shuffles, or any styling advice from the app.
- Social features, public profiles, sharing between members, resale.
- Virtual try-on or avatars.
- Shopping feeds, price tracking, buying inside the app.
- Android, iPad layouts, a laptop or web version.
- A public App Store listing.
- Open public sign-up and payments.
- Reminders and push notifications.
- Languages other than English.
- Style profile onboarding. Pinned, see section 19.

## 4. Users, accounts and admin

- **Member.** Anyone with an account. Sees only their own wardrobe, looks and inspirations. Nothing is shared between members.
- **Admin.** Marta. Adds people, manages invitations, sees totals (members, AI usage) and sets the monthly AI allowance. Never sees anyone's wardrobe or photos. The admin area is a section inside settings, visible only to the admin.
- **First testers.** Marta, in the Netherlands, and Sara, in Miami.

Installing:
- The app is shared through **TestFlight**, Apple's app for installing apps before they are in the App Store. Anyone with the TestFlight link can install it, but only invited emails can sign in.

Accounts:
- **Sign in with your email and a code, no password.** Enter your email, receive a 6-digit code, type it in (the iPhone offers to fill it from Mail). Until all 6 digits are in, a note under the field counts them ("5 of 6 digits."). You stay signed in until you sign out.
- **Invite only.** The admin adds a person by name and email. Caro emails them the TestFlight link and how to sign in. Signing in with an invited email for the first time starts onboarding. Invitations expire after 14 days.
- **Refused plainly.** Any other email, or one whose access was removed, gets "This email does not have access to Caro." at the email step, and no code. Each email can ask for at most 5 codes an hour; a new code replaces the one before.
- **Your data is yours.** Every member can download everything and delete their account, which deletes all their photos.

Admin area:
- **Members.** Name, email, place, joined, last active, AI actions this month.
- **Add person.** Name and email, then **Send invitation**.
- **Invitations.** Pending ones, with resend and cancel. Resend sends it again and opens it for another 14 days. Expired and cancelled ones are not listed: to invite that person again, add them again.
- **Remove access.** The person is signed out at once and can no longer sign in. Their data is kept for 30 days in case it was a mistake; the admin can restore access in that time. After 30 days everything is deleted, photos included, along with their invitation and sign-in codes. The admin's own access cannot be removed.

## 5. Onboarding

Designed for a new person the app knows nothing about. Every step is a check, not an assumption: the app proposes, the member confirms or changes. One step per screen, with "Step N of 6" and a progress line. Onboarding can be left and resumed: the app opens at the furthest step reached, with the earlier steps behind the back arrow. Choosing another city in onboarding takes you back to Your year, since the year must be confirmed again.

1. **Welcome.** After the first sign-in. The CARO wordmark, what Caro is in one line, who invited you, your name (prefilled from the invitation), and the privacy note: your photos are private, an AI service recognises your pieces in them, and it never styles you.
2. **Where you live.** Search for your city. The app shows what it works out from it: country, currency, date and size formats. **Looks right** or **Change**. Change corrects the currency, dates and sizes; the country follows the city, because store websites depend on it.
3. **Your year.** The app proposes your seasons from your city's typical weather, shown as 12 months with their typical high. Choose four seasons, two, or none; tap a month to move it to another season; rename a season. A line like "Now: hot and rainy, until the end of October" helps check it. For example:
   - The Netherlands: four seasons. Spring March to May, summer June to August, autumn September to November, winter December to February.
   - Miami: two seasons. Hot and rainy May to October, mild and dry November to April.
4. **Your stores.** First, which sections of the stores you shop in: **Women's**, **Men's**, **Unisex**, one or more. Nothing is chosen until you pick, and you pick at least one. This is about what you shop for, not about who you are. The sections are saved as you tap them. Then type the stores you shop at. For each, when you press return (each look-up is an AI action, so not while typing), the app finds its website for your country and shows it to confirm. A store with no online shop in your country, or one Caro cannot confirm, says so and is not searched. Remove any. **Skip for now** is allowed; stores and sections are only needed for the store search. **Continue** needs at least one section. Both go to step 5.
5. **Occasions.** Caro proposes four, explained: Office, Working from home, Night out, Day out. Keep the ones that fit, rename any, remove any or add your own: one to eight, each name once. Each can carry a short line under its name (up to 80 letters); a rename keeps the line, and the pencil changes both. Renaming an occasion keeps its pieces and looks; removing one takes it off them. An occasion still typed in the field is added when you press Continue or Save. In Settings, a centred "Occasions saved" confirmation lists them before going back.
6. **Your wardrobe.** The last and longest step, required before Looks and Get the look open.
   - How to photograph a piece: one piece per photo, flat or on a hanger, plain background, daylight.
   - **Take photos** (several in a row) or **Choose from library** (up to 50 at a time). The iPhone asks for camera access the first time, with Caro's line on why. Choosing from the library needs no access: the iPhone's photo picker shares only the photos you pick.
   - Caro cuts each piece out and suggests its details. You confirm them in the review queue: **Confirm**, change any detail, **Mark as maybe**, **Skip** (the piece waits for next time and does not count yet) or **Remove**. Where nothing lifted, **Retake** replaces the photo and keeps the details.
   - Progress is always visible: "12 of 20".
   - **Unlock rule.** Looks and Get the look open at 20 confirmed pieces that include at least one top, one bottom or one-piece, and one pair of shoes. The edit is always open.
   - It can take several sessions. Leaving shows the edit with the pieces so far, and Looks and Get the look locked with the progress and **Add pieces**.
   - Reaching 20 shows "Your wardrobe is open", then the app.

Settings repeats steps 1 to 5, plus download everything, delete account and sign out. The admin also sees the admin area.

## 6. Core concepts

- **Piece.** One piece of clothing, shoes, a bag or an accessory. Photo, cut-out, details. (`pieces` in the database.)
- **Chapter.** A category of pieces as the edit shows it, numbered 01 to 07: outerwear, knitwear, tops, trousers, dresses and skirts, shoes, accessories. These names replace the older ones on screens 07, 08 and 10 ("Shirts and tops", "Trousers and skirts", "Dresses", "Bags and accessories", and "Bottoms" on the review); here this file wins over the screens.
- **Kind.** What a piece is, inside its chapter: a jumper, a hoodie, a skirt. Each kind belongs to one chapter and fills one slot on the styling table. A kind is a filter inside a chapter, not a chapter of its own.

  | # | Chapter | Kinds | Slot on the styling table |
  |---|---|---|---|
  | 01 | Outerwear | coat, trench coat, puffer jacket, jacket, leather jacket, denim jacket, blazer, gilet | outer layer |
  | 02 | Knitwear | jumper, cardigan, knitted vest, knitted top, sweatshirt, hoodie | top |
  | 03 | Tops | shirt, blouse, t-shirt, long-sleeved top, tank top, bodysuit | top |
  | 04 | Trousers | trousers, jeans, shorts, leggings | bottom |
  | 05 | Dresses and skirts | dress, jumpsuit; skirt | one-piece; bottom |
  | 06 | Shoes | trainers, boots, ankle boots, loafers, ballet flats, heels, sandals, mules | shoes |
  | 07 | Accessories | bag; belt, scarf, hat, sunglasses, jewellery | bag; accessories |

  For the unlock rule, a top is anything in the top slot, a bottom anything in the bottom slot, and a one-piece a dress or jumpsuit.
- **Occasion.** Each member's own list, one to eight, starting from Caro's four: Office, Working from home, Night out, Day out. Each has a name and, if the member wants, a short line under it. Pieces and looks can have several.
- **Season.** Part of your year, set in onboarding from where you live: four seasons, two, or none. Pieces and looks can have several.
- **Look.** A set of pieces. Its source is built, photo or inspired. Can hold one or more photos of you wearing it. (`looks` in the database.)
- **Inspiration.** A photo of a look you like, an optional source link and a note.
- **Missing piece.** A piece in an inspiration you do not have.
- **To find.** The wishlist: missing pieces you marked as key, with products found in your stores. It lives inside Get the look. (`to_find` in the database.)
- **Store.** One of the stores a member shops at: a name and its website, such as cos.com, with its page for their country.
- **Invitation.** An email the admin has allowed to sign in.

In the app's words: the wardrobe is **the edit**, outfits are **looks**, the wishlist is **To find**.

## 7. Screens and flow

iPhone only, 390 points wide in the reference screens. Native iOS behaviour (navigation, sheets, the system camera and photo picker, Dynamic Type) with Caro's own visual language. Three main sections in a text tab bar: **The edit**, **Looks**, **Get the look**. Settings from the profile button in the masthead.

### Screen index

Designed screens are in `design/screens/` (source from the design canvas). Screens marked "to design" follow the same style; when building them, say what you added.

| # | Screen | Design file | Ticket |
|---|---|---|---|
| S1 | Sign in (email) | to design | T3 |
| S2 | Enter code | to design | T3 |
| S3 | Admin: members, add person, invitations | to design | T3 |
| 01 | Welcome | `01-welcome` | T4 |
| 02 | Where you live | `02-where-you-live` | T4 |
| 03 | Your year | `03-your-year` | T4 |
| 04 | Your stores | `04-your-stores` | T4 |
| S4 | Occasions (onboarding step 5) | to design | T4 |
| S5 | Settings | to design | T4, T8 |
| 05 | Your wardrobe | `05-your-wardrobe` | T5 |
| 06 | Adding pieces | `06-adding-pieces` | T5 |
| 07 | Review | `07-review` | T5 |
| 08 | The edit, still building | `08-edit-still-building` | T5 |
| 09 | Your wardrobe is open | `09-wardrobe-open` | T5 |
| 10 | The edit | `10-the-edit` | T6 |
| S6 | Chapter (all pieces in one category) | to design | T6 |
| 11 | Piece | `11-piece` | T6 |
| S7 | Wardrobe overview | to design | T6 |
| 12 | Style a look | `12-style-a-look` | T7 |
| 13 | Looks | `13-looks` | T7 |
| S8 | Look detail | to design | T7 |
| S9 | Look from a photo, confirm the pieces | to design | T9 |
| 14 | Get the look | `14-get-the-look` | T10 |
| S10 | Add inspiration, pieces found | to design | T10 |
| 15 | Your version | `15-your-version` | T10 |
| S11 | Find it (store results) | to design | T11 |

### The edit

- **10 The edit.** The masthead (profile, CARO wordmark, add), a double rule and the dateline ("The autumn edit · 96 pieces"). Contents: one numbered chapter per category with its count, "N not styled yet" when some pieces are in no look, and a few cut-outs.
- **08 The edit, still building (T5).** As screen 08, plus a line with the pieces still being read and the ones to review ("3 pieces to review", **Review**). Until T6, tapping a chapter opens a simple list of its pieces. Tapping a piece opens its details on the review form ("Your piece", **Save**), until T6 builds screen 11; touching and holding a piece removes it. T6 replaces the list with S6.
- **07 Review (T5).** As screen 07, plus Pattern in the Colour row, a Formality row, **Remove**, **Retake** for a photo where nothing lifted, and a button on the picture that turns it a quarter turn, for a photo taken sideways.
- **Camera (T5, to design).** The iPhone's own camera with a bar in Caro's ink: Done, the shutter, the last photo and how many were taken.
- **S6 Chapter.** All pieces in one chapter as cut-outs. Filters: kind (for example jumpers, cardigans, hoodies), season (current season by default), occasion, colour, maybe.
- **11 Piece.** The piece large, its details (seasons, occasions, colour, brand, size), the looks it is in. **Edit**. **Style a look with it** opens the styling table with this piece placed.
- **S7 Wardrobe overview.** Counts by category, colour, season and occasion. Pieces in no look yet. Occasions with fewer than three looks.

### Looks

- **13 Looks.** Masthead and dateline ("Looks · 34 looks"), occasions as a row of words, **Style a look**, and the saved looks as flat lays with their number, occasion and source (built, from your photo, from an inspiration).
- **12 Style a look.** The styling table: the pieces laid out as a flat lay with soft shadows, an empty dashed spot for an open slot, a rail of slots (outer layer, top, bottom, shoes, bag, accessories) and a tray of your pieces for the chosen slot, current season first. Occasion in the title ("A look for the office"), season chip. Starts empty or with the piece you came from ("Your starting piece"). **Save look**.
- **S8 Look detail.** The flat lay, your photos wearing it, occasions, seasons, the pieces. Edit, delete.
- **S9 Look from a photo.** Take or choose a photo of you wearing it; the pieces Caro spotted next to your photo, where a piece it is less sure of is asked about ("Is this your pale pink t-shirt?"), not ticked; remove any, add missing ones by chapter; occasions and seasons; save. If a look with the same main pieces exists: "You already have this look", and the photo is added to it.

### Get the look

- **14 Get the look.** Masthead and dateline, **Add an inspiration** (or share an image from Instagram or Pinterest), your inspirations with how much you own ("4 of 5 yours", "All yours"), and the To find list with each piece's state: not searched yet (**Find it**), options found, bought (**Add** to the edit).
- **S10 Add inspiration, pieces found.** The photo, an optional link and note. Each piece in the look described, next to the closest piece you own of the same kind, or "Not in your wardrobe". Change or remove any match.
- **15 Your version.** The inspiration with numbered pins. Below, your version as numbered credits: each piece marked yours, close or missing, with "For their grey oversized blazer". A missing piece shows your nearest piece of that kind, if you have one ("Your nearest: black knit jumper"), a fact ("in 3 of your inspirations") and **Find it**. Fill a missing piece yourself, or mark it as key. **Save** as a look.
- **S11 Find it.** Up to five products from your stores, in the sections you shop in: image, name, store, price in your currency, link to the store page (opens in Safari inside the app). "Nothing found" is a valid answer. The piece goes on To find.

### Settings and admin

- **S5 Settings.** Steps 1 to 5 of onboarding, download everything, delete account, sign out. Admin area for the admin.
- **S3 Admin.** Members, add person, invitations (section 4). Reached from Settings (S5), for the admin only.

## 8. Functional requirements

Pieces:
- Batch capture from the camera or multi-select from the photo library. Each photo becomes one piece.
- On the phone: the background is removed with the iPhone's own cut-out feature (the Vision framework, the same as touching and holding a subject in Photos). Free, fast, works offline. If nothing lifts from a photo, the piece keeps its photo as it is, on the tile colour, and can be retaken.
- On the server: resize to about 2000 px on the long side, strip location data, store original and cut-out, make a thumbnail.
- The app suggests a short name, chapter and kind, colours, pattern, material, warmth (light, medium, warm) and formality. Seasons are proposed from the warmth and the member's year (section 9). Occasions start empty: you choose them.
- Details are read on the server in the background, a few pieces at a time, so the member can keep adding photos. If Claude cannot answer, the piece waits for review with its details empty, for the member to fill in.
- The details come from fixed lists, so they can be counted and filtered:
  - Colours (up to three, main colour first, only as seen from the outside when worn): black, white, cream, beige, camel, brown, grey, navy, blue, light blue, green, olive, red, burgundy, pink, terracotta, orange, yellow, purple, silver, gold.
  - Patterns: plain, striped, checked, floral, polka dot, animal print, graphic, other pattern.
  - Materials: cotton, linen, wool, cashmere, silk, satin, denim, leather, suede, faux leather, viscose, polyester, nylon, canvas, straw, metal, not sure.
  - Formality: casual, smart casual, smart, formal.
  - A pair of shoes is one piece.
- Optional: brand, size (with its system, since EU and US sizes differ), price paid, notes.
- Pieces can be marked "maybe" to revisit after the clear-out.

Wardrobe overview:
- Counts by category, colour, season and occasion. Pieces in no look yet. Occasions with fewer than three looks. Facts only.

Built looks:
- Manual only. One piece per slot, several accessories.
- The flat lay is arranged automatically. No free drag and drop in version one.

Looks from a photo:
- Spotting pieces only looks at your own wardrobe. Best matches first; you confirm. A piece spotted with low certainty is asked about, not ticked.
- **Same look rule.** Two looks are the same when their main pieces are the same: outer layer, top, bottom or one-piece, shoes. Bag and accessories can change. A photo of a look you already have is added to it.

Inspired looks:
- The app describes each piece (kind, colour, pattern, material, shape) and compares it with the pieces you own of the same kind:
  - **Yours:** you own one of the same kind, colour and shape.
  - **Close:** you own one of the same kind and a similar colour (the same colour or a close shade, like cream and white), different in shape or material.
  - **Missing:** anything else, including the same kind in another colour. A missing piece still shows your nearest piece of that kind, if you have one.
  - Close does not count as yours.
- A missing piece shows a fact, not advice: "A piece like this is in 4 of your inspirations."
- You decide which missing piece is key.

Store search:
- Only on your tap, for one piece, in your stores, on your country's site.
- The search covers the store's whole website with your country set, and keeps only products in your currency, from the sections you shop in (women's, men's, unisex: chosen in onboarding, changed in settings). Children's sections are never searched. A search limited to the country page found nothing when that page was not the one the search engine knows.
- Each product page is then opened to get its image and to drop links that no longer work.
- Up to five results. "Nothing found" is a valid answer.
- If one of your stores has no online shop in your country, the search says so instead of showing products you cannot buy.
- Results are saved with the date found, since stock and prices change.

Onboarding, settings and admin:
- **Unlock rule.** 20 confirmed pieces, with at least one top, one bottom or one-piece, and one pair of shoes. Pieces skipped in the review queue do not count; pieces marked maybe do. Once open, Looks and Get the look stay open, even if pieces are removed later.
- Changing where you live in settings proposes a new year and new store websites. Nothing changes until you confirm: the new place and its year are saved together when you confirm the year, and each store keeps its old website, marked with the country it was found for, until you confirm its new one. The store search skips a store not checked for your country.
- If you change your seasons (for example from four to two), the app proposes new seasons for your pieces from their warmth at once (T5). Confirming them in one batch comes with the edit (T6), where pieces' seasons are shown.
- Invitations expire after 14 days. Removed members cannot sign in. A daily job deletes the data of members removed more than 30 days ago.

## 9. Places, seasons and stores

- **Any place.** Currency and formats come from the country. The Netherlands and Miami are where the first two testers live.
- **Your year is proposed from your city's weather,** from its typical monthly temperatures (and rain, where it matters more than cold). Southern hemisphere places work the same way.
  - The typical daily high and rain for each month come from Claude's memory (Sonnet), checked against Open-Meteo's 1991 to 2020 data. If the two differ by more than 3 °C in any month, Open-Meteo's numbers are used. Each city is looked up once and kept.
  - A rule in code, not the AI, proposes the seasons. Four meteorological seasons when the typical highs vary by 10 °C or more over the year, shifted by six months in the southern hemisphere. Otherwise two, when most of the rain falls in six months in a row, named from the temperature and rain ("Hot and rainy", "Mild and dry"). Otherwise none.
  - Each of the three can still be chosen. Where rain does not split the year, two seasons are the warmer and the cooler six months ("Warm" and "Cool").
  - With the same number of seasons, renaming a season or moving a month keeps its pieces and looks. With another number, the seasons are replaced (section 8).
- **Warmth connects pieces to seasons.** Warmth (light, medium, warm) means the same everywhere. A light linen shirt becomes spring and summer in the Netherlands, and both seasons in Miami. A rule in code, from the typical highs of the member's seasons (the average of their months):
  - Four seasons: light is the warmest season and the one before it, warm is the coldest season and the one before it, medium is all four. In the Netherlands: light is spring and summer, warm is autumn and winter.
  - Two seasons: light and medium are both, but light skips a season whose typical high is under 20 °C; warm is the cooler one.
  - No seasons: none.
- **The current season is a default filter.** It never hides pieces.
- **Stores are a personal list,** chosen by every member in onboarding. No shared catalogue. Marta's examples (Arket, COS, Uniqlo, Zara, Ganni, Bimba y Lola, Samsøe Samsøe) are sample content.
- **Local formats.** Dates, prices and sizes follow the member's country (12 Oct versus Oct 12, EU 38 versus US 8).

## 10. What the AI does and does not do

Does (on the server, through the Claude API):
- Suggest details for a new piece.
- Spot your pieces in a photo of you wearing a look.
- Describe the pieces of an inspiration and find the closest piece you own of the same kind.
- Find a store's website for your country.
- Search your stores for one piece (Claude's web search, limited to your stores' websites).
- Recall a city's typical monthly weather. The seasons themselves are proposed by a rule in code.

Not an AI service: cut-outs are made on the phone by the iPhone itself.

Does not:
- Suggest, rank or rate looks.
- Say what goes with what.
- Suggest buying anything you did not ask about.

Models, chosen in T1 (`docs/SPIKE.md`): Sonnet 5.5 for piece details, looks from a photo and inspirations; Haiku 5.5 for store websites and store search. The prompts start from the ones in `server/spike/`.

Limits: a monthly allowance of AI actions per member keeps costs predictable. The admin sets it. It starts at 300 a month; each piece, look, inspiration or search counts as one, and so do finding a store's website and recalling a city's weather (once per city, then kept). Every AI call is counted in `ai_usage` from T4; the allowance is enforced from T11. A typical month costs about 3 dollars per member.

## 11. Rules that must hold on the server

- Every request is scoped to the signed-in member. A member never reads or changes another member's data. The admin sees totals, never photos.
- Admin routes are checked on the server, not only hidden in the app.
- Only invited, active emails can sign in. Codes are stored hashed, expire after 15 minutes, and allow 5 attempts. At most 5 codes per email per hour. Session tokens are stored hashed too.
- Photos are private: served only to their owner through signed-in requests, never through public links. Location data is stripped before storing.
- The Claude API key lives only on the server, never in the app.
- There is no endpoint that generates or proposes looks.
- Store searches run only on an explicit request for one piece, only on the member's stores.
- The unlock rule is checked on the server. Once open, it stays open.
- The monthly AI allowance is enforced on the server.
- Removed members cannot sign in; their data is deleted 30 days after removal.

## 12. Data model

Lives on the server, in SQLite. Built in T2 by the numbered migrations in `server/src/db/migrations/`; later tickets change it with new ones. The tables use the app's words: pieces, looks, to find.

- Every row that holds a member's data has `user_id`, link tables included, so deleting a member deletes all of it.
- Invitations belong to the admin who sent them. Sign-in codes belong to an email, since an invited person has no account until their first sign-in.
- Dates are text in UTC and come from the server's clock, or `DEV_TODAY` in development. Prices are in cents.

Tables:
- Fixed lists, the same for everyone: `chapters`, `kinds` (chapter, slot), `colours`, `patterns`, `materials`, `proposed_occasions` (Caro's four, with their explanations; sections 5, 6 and 8). `settings`: the monthly AI allowance, one number for every member.
- `users`: email, name, role (member, admin), status (onboarding, active, removed), onboarding step, city (and its row in `cities`), country, currency, date order (30 Oct or Oct 30), size system (EU, US, UK, AU), store sections (women's, men's, unisex, each yes or no, all no until chosen), unlocked at, removed at, created, last active. Finishing step 5 makes a member active at step 6. `login_codes`: email, hashed code, expires, attempts, used. `sessions`: hashed token, created, last used.
- `invitations`: name, email, invited by, status (pending, accepted, cancelled, expired), sent, expires. One pending invitation per email.
- `occasions`: the member's own, name, line (optional, up to 80 letters) and order, one to eight. Pieces and looks point at them by id, so a rename keeps them.
- `seasons`: name, order. `season_months`: the season each month belongs to. A month is in one season at most, so seasons never overlap. Four, two or none per member.
- `stores`: name, domain (such as cos.com), the page for the member's country, sells online in the country (yes or no), the country it was checked for, order.
- `cities` and `city_weather` (T4): each city chosen from the city search (GeoNames id, region, country, coordinates, time zone, where its weather came from) and its typical high and rain for each month. Public facts kept once per city, not a member's data, so no `user_id`.
- `pieces`: name, kind (the chapter and slot follow from it), pattern, material, warmth, formality, brand, size, size system, price paid and its currency, notes, status (pending review, confirmed, maybe), details status (reading, suggested, not read; T5), photo paths (original, cut-out, thumbnail; no cut-out when nothing lifted). `piece_colours` (up to three, main first), `piece_occasions`, `piece_seasons`. The photo files live outside the database, in `DATA_DIR/photos/<member>/`: the photo as JPEG, the cut-out and the thumbnail as WebP.
- `looks`: number, source (built, photo, inspired), note. `look_pieces` (with slot: one piece per slot, several accessories). `look_occasions`, `look_seasons`. `look_photos`: photo, added.
- `inspirations`: photo, link, note. `inspiration_pieces`: pin number, description, kind, matched piece, match (yours, close, missing), key.
- `to_find`: from inspiration piece, status (considering, bought, dropped), last searched (empty means not searched yet). `store_results`: store, name, price, currency, link, image, found at.
- `ai_usage`: action, date.

To add with the ticket that needs it: an occasion on inspirations (T10, screen 14 shows one), pin positions on the inspiration photo (T10).

## 13. Notifications

Email only, through Resend: sign-in codes and invitations. In development, emails are printed in the terminal instead of being sent. No reminders or push notifications.

## 14. Non-functional and privacy

- iPhone only, iOS 17 or later (the cut-out feature needs it). Test in the iPhone Simulator and on Marta's iPhone.
- The app needs a connection to save. Photos already seen are kept on the phone, so browsing stays fast.
- Photos of you wearing looks show people, so treat them as personal data.
- A short privacy note in the welcome step, saying plainly that photos are sent to an AI service to be analysed.
- Download everything (a zip of data and photos) and delete account.
- Nightly backup of the database and photos. This data lives for years.
- A `DEV_TODAY` setting on the server to pretend it is another date, so seasons can be tested.
- Running costs: the Apple Developer Program (99 US dollars a year, needed for TestFlight from T8), a small server with a disk, and AI usage.
- TestFlight builds expire after 90 days, so a new build goes out at least every three months.

## 15. Design system

The look is "Spread": your closet as a magazine. Exact values are in `design/tokens.json` and in the screens.

- **Brand.** Sara Caro's CARO wordmark: `design/assets/caro-wordmark-ink.png` (a cleaned, transparent version). Ask Sara for the vector file (SVG or PDF) for the app; never redraw or recolour it.
- **Colour.** Paper `#F7F2E9` (background), ink `#161514` (text, primary buttons, rules), muted `#6B645C` (secondary text), hairline `#DCD2C2`, tile `#EFE7DB` (behind cut-outs, the styling table), photo `#D3C7B6` (inspiration placeholder), terracotta `#9A5E48` (missing pieces, Find it, warnings, small links). Season swatches use Sara's palette: terracotta `#B4765F`, sand `#D9B986`.
- **Type.** Bodoni Moda for display (titles 30 to 34, chapter names 21, chapter numbers 30, italics for the emphasised word: "Your *version*"). Inter for everything else (body 14 to 15, labels 11 in capitals with wide spacing). Both are open-licence Google Fonts; bundle them in the app and support Dynamic Type.
- **Shapes.** Tiles and cards 4 pt corners. Pill buttons 52 pt high (primary ink, secondary outlined). Chips 32 pt high. Page margin 20 pt. Hairlines between rows.
- **Signature parts.** The masthead (profile, wordmark, add) with a double rule and a dateline; numbered chapter rows; cut-outs with a soft shadow (0, 8, 9, warm brown at 22%); numbered credits; dashed empty slots; a text tab bar with an underlined current section.
- **Copy.** Sentence case, no em dashes, no emoji, no exclamation marks. Use the app's words: the edit, looks, get the look, to find, piece.

## 16. Stack

Claude Code confirms or adjusts this in T0.

- **iPhone app.** Swift and SwiftUI in Xcode, iOS 17 or later. Vision for cut-outs, PhotosPicker and the camera, a share extension for inspirations (T10), the Keychain for the session.
- **Server.** Node 22, Express, SQLite (better-sqlite3), sharp for images, Resend for email, the Anthropic SDK for the Claude API. The same family as the Unspoken Diary, now answering the app with JSON instead of rendering pages.
- **Hosting.** Render, with a persistent disk for the database and photos. Secrets in Render's environment settings.
- **Distribution.** TestFlight.
- **Repository.** One Git repository with two folders: `app/` and `server/`. GitHub for history.

## 17. Build plan: tickets

One ticket at a time, each small enough to build, test and commit on its own. Each starts in plan mode, on its own Git branch. "Done when" is what Marta checks before the next one starts.

### Phase 1: the wardrobe

**T0. Project setup.**
Both halves run on Marta's Mac and talk to each other.
- Git repository, `.gitignore`, `README.md`.
- `server/`: Express with a health route, `.env.example`, `npm run dev`.
- `app/`: an Xcode SwiftUI project with Bodoni Moda and Inter bundled and the colours from `design/tokens.json`.
- A hello screen in Caro's style that calls the server.
Done when: the app in the iPhone Simulator shows the CARO wordmark, "Hello, Marta" in Bodoni and "Server connected". The same on Marta's iPhone on the same wifi.

**T1. AI spike.**
Know how well recognition works before building on it. Scripts in `server/spike/`, no screens.
- Details for 15 real pieces.
- Spotting pieces in 5 photos of looks being worn.
- Matching 5 inspirations against those 15 pieces.
- Finding store websites in the Netherlands and the US, and searching one piece in each.
- Proposing a year for Amsterdam, Miami and one southern hemisphere city.
- By hand: the cut-out quality of the iPhone's own feature on the same 15 photos.
Chooses the Claude model, the prompts and the climate data source.
Done when: `docs/SPIKE.md` shows the results per test, what works and what does not, the cost per action, and recommendations. Marta has read it. Anything it changes goes into this PRD before T5.

**T2. Database and seed.**
- The schema for section 12.
- Seed: Marta as admin (Netherlands, four seasons, her example stores) and a pending invitation for a test Sara.
- `npm run seed` and `npm run reset-dev`. `DEV_TODAY`.
Done when: the seed prints the admin and the invitation, and the tables can be opened in a database viewer.

**T3. Sign in and admin.**
- Email and 6-digit code (printed in the terminal in development), hashed, 15 minutes, 5 attempts.
- The session kept in the iPhone Keychain. Sign out.
- Only invited, active emails can sign in.
- Admin area: members, add person, invitations (send, resend, cancel, 14-day expiry), remove access and restore within 30 days, the daily clean-up job.
- Screens S1, S2, S3. Until S5 (T4), the admin area is reached from a temporary settings sheet behind the profile button.
Done when: Marta signs in with the code from the terminal; adds a test person; that email signs in and lands in onboarding; any other email is refused; a removed person cannot sign in, and restoring them works.

**T4. Onboarding: set up.**
- Steps 1 to 5: welcome and name, where you live, your year, your stores, occasions.
- City search, the worked-out country, currency and formats.
- The proposed year: four, two or none seasons; move months; rename seasons.
- Stores: the sections you shop in (women's, men's, unisex, at least one), add, find the website for the country, "no online shop in your country", remove, skip.
- Resume where you stopped. Settings (S5) repeats steps 1 to 5.
- Screens 01 to 04, S4, S5.
Done when: as the test Sara in the Simulator, with `DEV_TODAY=2026-10-30`: Miami, two seasons, "Now: hot and rainy", add two stores, close the app, reopen it, and it resumes at the same step.

**T5. Onboarding: your wardrobe.**
- Tips, **Take photos** (batch) and **Choose from library** (multi-select), with the permission prompts.
- Cut-out on the phone, upload, server processing (resize, strip location, thumbnail).
- Suggested details and seasons from warmth.
- Adding pieces (processing), the review queue (confirm, edit, skip, maybe), progress.
- The unlock rule on the server, the locked tabs, "Your wardrobe is open".
- Screens 05 to 09. `npm run seed-wardrobe` gives a member 19 drawn pieces and no shoes, locked again, to test the unlock.
Done when: on Marta's iPhone, she photographs 5 real pieces, sees them cut out, confirms them and sees the count go up. With 19 seeded pieces and no shoes, adding a pair of shoes opens Looks and Get the look. Removing pieces afterwards keeps them open.

**T6. The edit.**
- Contents by chapter with counts and "not styled yet".
- Chapter page with filters (current season by default, occasion, colour, maybe).
- Piece page: details, looks it is in, edit, mark maybe, delete.
- Wardrobe overview.
- Screens 10, 11, S6, S7.
Done when: with the seeded wardrobe, Marta opens a chapter and a piece, edits its name and occasions, and sees the counts change. Changing the season filter changes what shows.

**T7. Looks.**
- The styling table: slots, the tray for the chosen slot (current season first), the automatic flat lay, occasion and seasons, **Save look**.
- Start empty or from a piece (**Style a look with it**).
- Looks by occasion, with source; look detail with edit and delete.
- Screens 12, 13, S8.
Done when: from the camel coat's page, Marta taps **Style a look with it**, adds a shirt, trousers and shoes, saves, finds the look under Office, and sees "In 1 look" on the coat.

**T8. Online and TestFlight.**
- The server on Render with a persistent disk and HTTPS; secrets in Render.
- Resend for codes and invitations.
- Nightly backup. Download everything. Delete account.
- The app pointing at the online server. The app icon, from the wordmark.
- Apple Developer Program, the first TestFlight build. Invite Sara.
Done when: Marta signs in on her iPhone against the online server with an emailed code. Sara receives the invitation, installs from TestFlight in Miami, and onboards. A backup file exists. Download everything gives a zip.

### Phase 2: looks from a photo

**T9. Look from a photo.**
- Take or choose a photo of you wearing a look.
- Spotted pieces from your own wardrobe, confirm, occasions and seasons, save.
- The same look rule. Photos on the look detail.
- Screen S9.
Done when: a photo of Marta wearing 4 of her pieces suggests those pieces; confirming saves a look with the photo; a second photo of the same look is added to it instead of making a new one.

### Phase 3: Get the look

**T10. Get the look.**
- Get the look home: inspirations with "N of M yours", the To find list.
- Add an inspiration from the library and from the share sheet (a share extension).
- Pieces found, your version with pins and credits (yours, close, missing), fill a missing piece yourself, mark as key, save as a look.
- The "in N of your inspirations" fact.
- Screens 14, 15, S10.
Done when: Marta shares an image from Pinterest into Caro, sees the pieces found and her version as credits, marks the missing piece as key, and saves the look.

**T11. Find it and To find.**
- Search one key piece in the member's stores, on the country site.
- Up to five results, "no online shop in your country", results saved with their date.
- To find statuses; **Bought** starts adding the piece to the edit.
- The monthly AI allowance enforced, and AI usage visible to the admin.
- Screen S11.
Done when: as Marta, **Find it** on a missing bag shows results from her stores in euros, with links that open in Safari. As Sara, the same search shows US results in dollars. With the allowance used up, a clear message appears instead.

**Later.** Style profile, reminders, open sign-up, an App Store listing.

## 18. Open decisions and defaults

Defaults taken to start building. Change them before the ticket that needs them.
- **Sign-in:** email code (T3). Sign in with Apple would also work, but invitations are by email.
- **Look from a photo:** kept as a way to create looks (T9).

Decided in T1 (see `docs/SPIKE.md`):
- Cut-outs: the iPhone's own feature, as planned (on Marta's 16 photos: 12 good, 4 fair, none failed). When nothing lifts, the piece keeps its photo on the tile colour and can be retaken (section 8).
- Models: Sonnet 5.5 for anything with photos, Haiku 5.5 for store websites and search (section 10).
- Seven chapters with short names, kinds as a filter inside each, cardigans always a top (section 6).
- Fixed lists for colours, patterns, materials and formality (section 8).
- Close means the same kind and a similar colour (section 8).
- Store search covers the whole store website, in the sections each member shops in: women's, men's, unisex, chosen in onboarding (sections 5 and 8).
- Your year: Claude's memory for the weather, checked against Open-Meteo, and a rule for the seasons. Miami stays "mild and dry" (section 9).
- The allowance starts at 300 AI actions a month (section 10).

Needed from Sara:
- The vector file of the wordmark, before T8 (app icon).

Decided:
- Caro is wardrobe management and look creation. No daily log, no timeline, no wear statistics.
- Spread is the design, with Studio's styling table as the look builder. Three sections: The edit, Looks, Get the look; the wishlist lives inside Get the look as To find.
- Building the wardrobe is part of onboarding. Looks and Get the look unlock at 20 confirmed pieces with a top, a bottom or one-piece, and shoes.
- A native iPhone app, shared through TestFlight. Both testers are on iPhone.
- No reminders or push notifications for now.
- Invite only; the admin adds people and manages invitations. Removed members' data kept 30 days, restorable, then deleted.
- Any place; onboarding proposes where you live and your seasons, and the member confirms. Seasons per member: four, two or none.
- Every member chooses their stores in onboarding. No shared catalogue.
- The same look rule: same outer layer, top, bottom or one-piece, and shoes.
- Each member's own occasions, starting from Caro's four (changed in T4, after testing).
- Looks are an automatic flat lay, no free drag and drop.

## 19. Pinned: style profile

Not in version one. A short onboarding step to help a member see their own patterns, never to steer suggestions. Frameworks to research: the three-word method (Allison Bornstein), seasonal colour analysis, Kibbe and Kitchener essences (reference only), capsule wardrobes, and the member's own data once there are enough looks and inspirations.

---

## Changes

- **v0.2.** The AI never styles. Three ways to make an outfit. Outfit of the day log and analytics. Countries and seasons. Accounts.
- **v0.3.** Invite only. The Netherlands and the US. Same outfit rule. The same four occasions for everyone. Auto collage.
- **v0.4.** Miami's climate for the US.
- **v0.5.** Stores as a personal list. Marta and Sara as the first testers.
- **v0.6.** Onboarding for anyone, anywhere. Every member chooses their stores. Admin area. Removed members' data kept 30 days.
- **v0.7.** Named Caro Styling. A native iPhone app through TestFlight, cut-outs on the phone, a server for accounts, data and AI. Sign-in by emailed code. Share sheet for inspirations. No reminders.
- **v0.8.** New value proposition: a styling studio for the clothes you already own. No outfit log, timeline or wear statistics. A wardrobe overview instead.
- **v0.9.** Spread chosen. Three sections: The edit, Looks, Get the look (with To find inside). Style a look with it from any piece.
- **v0.10.** Building the wardrobe is the last, required onboarding step, unlocking at 20 pieces.
- **v1.0.** Ready to build. Screen index linked to the design files, rules that must hold on the server, the design system, the stack, tickets T0 to T11 with what to check, defaults for the last open decisions.
- **v1.1.** From the T1 spike. Seven chapters with short names (Knitwear, Tops, Trousers, Dresses and skirts, Accessories) and kinds as a filter. Fixed lists for the details. A stricter close. Store search on the whole store website, in the sections each member chooses in onboarding (women's, men's, unisex). Your year from Claude's memory and a rule. Models per action. An allowance of 300. Cut-outs stay on the phone, with the photo itself as the fallback. The chapter names change on screens 07, 08 and 10, and screen 04 gets the section chips above the store list.
- **v1.2.** From T2. The database tables use the app's words: `pieces`, `looks`, `to_find`. Section 12 matches the tables as built: the fixed lists as tables, the allowance as one setting for every member, store domains, store sections as three yes or no choices, months per season, sign-in codes kept by email, last searched on To find, prices in cents.
- **v1.3.** From T3. A refused email is told plainly at the email step; at most 5 codes per email per hour. Resend opens an invitation for another 14 days; only pending invitations are listed. Removing access signs the person out at once; the admin's own access cannot be removed; after 30 days the invitation and codes for that email go too. Admin routes are checked on the server. Until S5, the admin area is reached from a temporary settings sheet.
- **v1.4.** From T4. Change on Where you live corrects currency, dates and sizes; the country follows the city. Resume at the furthest step; another city in onboarding goes back to Your year. Stores are looked up on return, sections saved on each tap, Continue needs a section, Skip for now and Continue go to step 5, and a store Caro cannot confirm is not searched. In settings, a new place is saved with its year, and stores keep their old site until confirmed. Every option of the year can be chosen. Store websites and city weather count as AI actions. Section 12: city, formats and checked country added, with the `cities` and `city_weather` tables. Occasions are each member's own: Caro proposes four, and the member keeps, renames, removes or adds, one to eight (`proposed_occasions` and `occasions`); each keeps an editable line under its name, and Settings confirms the save. S2: a note under the code field counts the digits until there are 6.
- **v1.5.** From T5. Take photos takes several in a row; Choose from library needs no permission (the photo picker shares only what you pick). The review queue: Skip leaves a piece waiting, Remove, Retake keeps the details; screen 07 adds Pattern, Formality, Remove and Retake. The edit shows the pieces to review; until T6 a simple chapter list lets a piece be opened, changed and saved, or removed. Any piece's pictures can be turned a quarter turn. Seasons from warmth: the warm half and the cool half of the member's year. Changing the number of seasons proposes new ones at once; the batch confirmation comes in T6. Details are read in the background; a piece Claude could not read waits for the member to fill in. Section 12: details status on pieces, photo files under `DATA_DIR/photos/`. `npm run seed-wardrobe`.
