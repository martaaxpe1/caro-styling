-- 013: already in the edit (PRD sections 7 and 8). Added in T14.
--
-- A piece waiting for review (piece_id) that looks like one the member already has (other_id),
-- in the edit or also waiting. Review asks about it: "same" joins the two, and the row goes with
-- the new piece; "different" is kept, so those two are not asked about again.

CREATE TABLE piece_lookalikes (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  piece_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  other_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  certainty TEXT NOT NULL CHECK (certainty IN ('high', 'medium')),
  answer TEXT CHECK (answer IN ('different')),  -- empty: not answered yet
  created_at TEXT NOT NULL,
  PRIMARY KEY (piece_id, other_id),
  CHECK (piece_id <> other_id)
) STRICT;

CREATE INDEX piece_lookalikes_other ON piece_lookalikes (other_id);
