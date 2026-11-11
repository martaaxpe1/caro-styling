-- 005: each occasion keeps its own one-line explanation. Added in T4, after testing.
--
-- Before, only Caro's four had a line, and a renamed one lost it. Now the line belongs to the
-- member's occasion: it stays when the occasion is renamed, and the member can write or change
-- it, for their own occasions too. Empty means no line.

ALTER TABLE occasions ADD COLUMN description TEXT;

-- Occasions that still have one of Caro's names start with Caro's line.
UPDATE occasions SET description = (
  SELECT p.description FROM proposed_occasions p WHERE lower(p.name) = lower(occasions.name)
);
