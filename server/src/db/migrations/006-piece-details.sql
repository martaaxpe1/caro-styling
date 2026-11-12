-- 006: pieces get their details from Claude in the background (PRD sections 5, 8 and 10). Added in T5.
--
-- A new piece is saved as soon as its photo arrives, then a queue on the server asks Claude
-- for its details (src/jobs/piece-queue.js). details_status says how far that got:
-- - reading: waiting for Claude, or being read now
-- - suggested: Claude's details are in; the member checks them in the review queue
-- - not read: Claude could not answer; the member fills in the details
-- This is separate from status (pending, confirmed, maybe), which is the member's decision.

ALTER TABLE pieces ADD COLUMN details_status TEXT NOT NULL DEFAULT 'reading'
  CHECK (details_status IN ('reading', 'suggested', 'not read'));

-- So the queue finds the pieces still waiting quickly, for example when the server restarts.
CREATE INDEX pieces_reading ON pieces (details_status) WHERE details_status = 'reading';
