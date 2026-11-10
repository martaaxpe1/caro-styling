# Design screens

Exported from the Caro Styling design canvas: https://claude.ai/artifact/2Z4LEXpkUS6eCRP6co1kkC

Each `.dc.html` file is one iPhone screen at 390 by 844 points, written for the web canvas. Read them for layout, sizes, colours and copy, then rebuild them in SwiftUI. Do not copy the HTML into the app.

How to read them:
- The markup between `<x-dc>` and `</x-dc>` is the screen. Inline styles hold the exact values.
- `{{name}}` is a placeholder filled from the script at the bottom (`renderVals()`), which holds the sample content: lists, cut-out shapes, positions.
- The clothes are simple drawn shapes standing in for real cut-out photos.
- `/_blob/...` images are the CARO wordmark: use `design/assets/caro-wordmark-ink.png` (or the vector file from Sara, when it arrives).
- Links between screens use the canvas file names (`O-Place.dc.html`, `B-Piece.dc.html` and so on). The table maps them.
- The sample person is Sara, in Miami: two seasons, US formats.

| # | File | Screen | Canvas name | Ticket |
|---|---|---|---|---|
| 01 | `01-welcome.dc.html` | Welcome | O-Welcome | T4 |
| 02 | `02-where-you-live.dc.html` | Where you live | O-Place | T4 |
| 03 | `03-your-year.dc.html` | Your year | O-Year | T4 |
| 04 | `04-your-stores.dc.html` | Your stores | O-Stores | T4 |
| 05 | `05-your-wardrobe.dc.html` | Your wardrobe | O-Wardrobe | T5 |
| 06 | `06-adding-pieces.dc.html` | Adding pieces | O-Adding | T5 |
| 07 | `07-review.dc.html` | Review | O-Review | T5 |
| 08 | `08-edit-still-building.dc.html` | The edit, still building | O-Locked | T5 |
| 09 | `09-wardrobe-open.dc.html` | Your wardrobe is open | O-Unlocked | T5 |
| 10 | `10-the-edit.dc.html` | The edit | B-Wardrobe | T6 |
| 11 | `11-piece.dc.html` | Piece | B-Piece | T6 |
| 12 | `12-style-a-look.dc.html` | Style a look | B-StyleLook | T7 |
| 13 | `13-looks.dc.html` | Looks | B-Looks | T7 |
| 14 | `14-get-the-look.dc.html` | Get the look | B-GetTheLookHome | T10 |
| 15 | `15-your-version.dc.html` | Your version | B-GetTheLook | T10 |

Screens not designed yet (S1 to S11 in the PRD's screen index) follow the same style. When building one, say what you added.
