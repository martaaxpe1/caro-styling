# UI audit (12 Nov 2026)

A UI-only audit of the iPhone app with impeccable, before the first TestFlight build reaches Sara. Nothing here changes a flow, a screen, what a screen holds, its order, its behaviour or its copy.

- Branch `ui-audit`, from `t8-online`. Not pushed, not merged.
- Checked in the iPhone 17 Pro Simulator (iOS 26.2) against a scratch copy of the server, at the normal text size and at a large accessibility size. Not checked on a real iPhone.
- Screenshots, before and after: the private page "Caro UI audit" (https://claude.ai/artifact/3Aixov2NNjs5nY7oMdFPNM).
- Score before: 14 of 20 (accessibility 2, performance 3, colour and theming 3, native iOS 3, adapting 3).

## What changed

| # | Finding | Change | Departs from the design files |
|---|---|---|---|
| 1 | Large text broke a few layouts | Icons next to text grow with the text size (up to twice). Chapter, credit and overview numbers never split over two lines. At the largest sizes the edit's cut-outs move under the chapter name. The profile circle grows with its initial. Masthead and tab bar grow up to the largest standard size, then show large on touch and hold. Detail rows get room above and below. | No, at the normal size. Yes at accessibility sizes: the edit's cut-outs sit under the chapter name. |
| 2 | Locked tabs at 2 to 1 | Locked Looks and Get the look stay in muted (5.2 to 1), with the lock. Still not tappable. | No: muted is the token the design gives them. |
| 3 | Disabled buttons a cool grey | A pill that cannot be pressed yet is hairline with muted words. | Yes: new state, `parts.disabledButton` in tokens.json. |
| 4 | Placeholders at 2 to 1 | New `placeholder` colour #786D5F (4.5 to 1 on paper). | Yes: new token. The design used outline. |
| 5 | Toolbar buttons differed | Kept the iOS 26 glass buttons (Marta's choice). Style a look's Cancel is now a glass button too. | Yes: the design has plain ink. iOS 26 draws these. |
| 6 | Content under the clock | No change needed. On a second look the edit already has a paper strip behind the clock, and Looks keeps its masthead fixed. | No |
| 7 | Terracotta on tile at 4.2 to 1 | New `terracottaOnTile` #8E5642 (4.8 to 1): the store look-up note and an open slot's name on the styling table. Terracotta on paper is unchanged. | Yes: new token. Screen 12's slot name was #9A5E48. |
| 8 | Empty Looks was one grey line | The same words inside a dashed spot as tall as a look, in the empty-slot style. Also for an occasion with no looks. | Yes: added to a screen the design does not show. |
| 9 | Design colours not in tokens.json | `colour.details` in tokens.json and named colours in the app: drawingNavy, addingWaiting, addingWorking, tagPaper, tagEdge, shadowBrown. No visible change. | No: the values come from the design files. |

`design/tokens.json` matches the app: `app/Caro/Design/CaroColor.swift` holds every colour in it by name, and nothing in `app/Caro/Features/` writes a colour by hand. The 21 swatches for a piece's colour (black, camel, navy...) stay in `app/Caro/Design/PieceColours.swift`: they show what colour a piece is, so they are content, not part of the design system.

## Not changed, for Marta

- **Copy.** Get the look says "Get the look comes in T10." Sara will see it in TestFlight. A suggestion, for Marta to word: "Get the look is coming in a later version."
- **Out of scope (UX).** In Review, the next piece opens where the last one was scrolled to, not at its photo.

## Checks

- Clean builds for the Simulator (Debug) and a device (Release, unsigned): no warnings.
- `npm test` in `server/`: 87 of 87 pass. `server/` is untouched.

## Proposed for the PRD

Section 15, Colour, add after terracotta: "Placeholder `#786D5F` (example text in empty fields); terracotta on tile `#8E5642` for small text on the tile colour."

Section 15, Shapes, add: "A pill that cannot be pressed yet is hairline with muted words."

Changes log:

- **v1.9.** From the UI audit. Readable example text in empty fields and a deeper terracotta for small text on the tile colour, both new tokens. Buttons that cannot be pressed yet are hairline with muted words. Locked tabs stay readable. Icons and numbers follow the iPhone's text size; at the largest sizes the edit's cut-outs move under the chapter name. Toolbar buttons follow iOS 26 (glass). Empty Looks shows its line in a dashed empty spot. The design files' detail colours are named in tokens.json.

## Display font: Newsreader (after the audit)

Marta found the look too close to the AI default (cream, a thin Didone, terracotta). She chose direction B, fonts only: Newsreader replaces Bodoni Moda for every display style (titles, chapter names and numbers, section titles, fields, the sign-in code). Inter, sizes, layout, colours, copy and behaviour are unchanged; the italic emphasised word stays, in Newsreader italic.

- Why: Bodoni Moda is a poster Didone whose hairlines go spindly at 18 to 34 points. Newsreader is a variable serif with optical sizes, made for screens, so titles hold up at phone sizes.
- Files: `app/Caro/Resources/Fonts/Newsreader.ttf`, `Newsreader-Italic.ttf` and `OFL-Newsreader.txt` (SIL Open Font Licence, from Google Fonts); Bodoni Moda's files are removed. `CaroFont.swift` and `Info.plist` point at Newsreader; `design/tokens.json` `type.display` says Newsreader.
- Departs from the design files: yes, every screen's display type. The canvas screens in `design/screens/` still show Bodoni Moda.
- Comparison of the candidates: https://claude.ai/artifact/1hmzVeUJbhpPEgUX25vkEP (private to Marta).

Proposed for the PRD: section 15, Type: "Newsreader for display (titles 30 to 34, chapter names 21, chapter numbers 30, italics for the emphasised word: "Your *version*")." Add to the v1.9 entry: "Newsreader replaces Bodoni Moda for display type, so titles hold up at phone sizes; the canvas screens still show Bodoni."
