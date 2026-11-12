-- 009: Get the look (PRD sections 6 to 8, screens 14 and 15). Added in T10.
--
-- An inspiration is saved as soon as its photo arrives; Claude then reads it in the background
-- (src/jobs/inspiration-queue.js). status says how far that got:
-- - reading: waiting for Claude
-- - ready: the pieces are described and compared with the member's own
-- - not read: Claude could not answer; the member can try again
-- Rows from before this migration had no reading step, so they start as ready.

ALTER TABLE inspirations ADD COLUMN status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('reading', 'ready', 'not read'));
-- The occasion the member gives it (screen 14 shows one under each inspiration).
ALTER TABLE inspirations ADD COLUMN occasion_id INTEGER REFERENCES occasions (id) ON DELETE SET NULL;
-- The look saved from it ("your version"), if any. The look can be deleted on its own.
ALTER TABLE inspirations ADD COLUMN look_id INTEGER REFERENCES looks (id) ON DELETE SET NULL;

CREATE INDEX inspirations_reading ON inspirations (status) WHERE status = 'reading';

-- What Claude saw in each piece, for the credits and for the fact "in 3 of your inspirations"
-- (same kind and main colour).
ALTER TABLE inspiration_pieces ADD COLUMN colour TEXT REFERENCES colours (name);
ALTER TABLE inspiration_pieces ADD COLUMN shape TEXT;
-- Where the numbered pin goes on the photo: the piece's centre, in percent of the width and height.
ALTER TABLE inspiration_pieces ADD COLUMN pin_x INTEGER CHECK (pin_x BETWEEN 0 AND 100);
ALTER TABLE inspiration_pieces ADD COLUMN pin_y INTEGER CHECK (pin_y BETWEEN 0 AND 100);
-- The member's own choice for this piece: a missing piece filled with one of theirs, or a
-- match changed. It wins over Claude's match.
ALTER TABLE inspiration_pieces ADD COLUMN filled_piece_id INTEGER REFERENCES pieces (id) ON DELETE SET NULL;
-- Taken out of "your version" by the member. Kept, so it can be put back.
ALTER TABLE inspiration_pieces ADD COLUMN removed INTEGER NOT NULL DEFAULT 0 CHECK (removed IN (0, 1));
