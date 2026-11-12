-- 007: seasons to check (PRD section 8). Added in T6.
--
-- When a member changes the number of their seasons (for example from four to two), every
-- piece gets new seasons proposed from its warmth at once (T5). Those proposals are marked
-- here, so the edit can ask the member to check them in one batch. Saving the piece, or
-- confirming the batch, clears the mark.

ALTER TABLE pieces ADD COLUMN seasons_to_check INTEGER NOT NULL DEFAULT 0
  CHECK (seasons_to_check IN (0, 1));
