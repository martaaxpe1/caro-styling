# Test 6: iPhone cut-outs, by hand

The app will cut each piece out of its photo on the iPhone itself, with the same feature as touching and holding a subject in the Photos app. This test checks how good those cut-outs are on your 16 piece photos, before we build on it.

It takes about 15 minutes. No code, no cost.

## How to do it

On your iPhone, for each of the 16 piece photos (the same ones as in `photos/pieces/`):

1. Open the photo in the Photos app.
2. Touch and hold the piece until a glowing outline runs around it, then lift your finger. A small menu appears.
3. Tap **Copy**.
4. Open a new note in the Notes app and paste. The cut-out appears on the white page.
5. Pinch to zoom in on the edges, and rate it with the scale below.

If nothing glows after a second or two, the iPhone did not find a subject: that is "failed".

Optional: in step 3, tap **Share**, then **Save Image**, to keep the cut-out in Photos. AirDrop the saved cut-outs to the Mac and put them in `server/spike/photos/cutouts/`. That folder is ignored by Git, like the other photos.

## The scale

- **Good:** the whole piece, clean edges, no background. Usable as it is.
- **Fair:** the whole piece with small flaws: a little background, a rough edge, a bit of hanger.
- **Poor:** part of the piece is missing, or a lot of background is left.
- **Failed:** nothing lifts, or the wrong thing lifts (the hanger, the background, a person).

## Your results

Fill in the table here, or just tell Claude in chat ("1 good, 2 fair, the strap is cut off...").

How you took the photos (flat or on a hanger, the background, the light):

| # | Piece | Result | Notes |
|---|---|---|---|
| 01 | | | |
| 02 | | | |
| 03 | | | |
| 04 | | | |
| 05 | | | |
| 06 | | | |
| 07 | | | |
| 08 | | | |
| 09 | | | |
| 10 | | | |
| 11 | | | |
| 12 | | | |
| 13 | | | |
| 14 | | | |
| 15 | | | |
| 16 | | | |

Anything else you noticed (speed, which kinds of pieces were hard):
