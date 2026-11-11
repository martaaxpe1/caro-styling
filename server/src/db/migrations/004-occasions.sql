-- 004: each member's own occasions (PRD sections 5 and 6). Added in T4.
--
-- Before: four fixed occasions, the same for everyone. Now: Caro proposes four, and each
-- member keeps the ones that fit, renames any, removes any or adds their own, one to eight.
-- - proposed_occasions: Caro's four, with a line to explain each. The same for everyone.
-- - occasions: each member's own list, like their seasons and stores.
-- Pieces and looks now point at the member's occasion by its id, so renaming an occasion
-- keeps its pieces and looks. No member had pieces or looks yet, so no data really moves;
-- the copies below are there to be safe.


-- 1. The fixed list becomes Caro's proposal.
ALTER TABLE occasions RENAME TO proposed_occasions;


-- 2. Each member's own occasions. A name only once per member, whatever its capitals.
CREATE TABLE occasions (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name TEXT NOT NULL COLLATE NOCASE,    -- Office, or the member's own, like Travel
  position INTEGER NOT NULL,
  UNIQUE (user_id, name)
) STRICT;

-- Every member so far starts with Caro's four, named as they show: Office, Working from home, ...
INSERT INTO occasions (user_id, name, position)
  SELECT users.id, upper(substr(p.name, 1, 1)) || substr(p.name, 2), p.position
  FROM users CROSS JOIN proposed_occasions p
  ORDER BY users.id, p.position;


-- 3. Pieces and looks point at the member's occasion by id.
CREATE TABLE piece_occasions_new (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  piece_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  occasion_id INTEGER NOT NULL REFERENCES occasions (id) ON DELETE CASCADE,
  PRIMARY KEY (piece_id, occasion_id)
) STRICT;

INSERT INTO piece_occasions_new (user_id, piece_id, occasion_id)
  SELECT po.user_id, po.piece_id, o.id
  FROM piece_occasions po JOIN occasions o ON o.user_id = po.user_id AND o.name = po.occasion;

DROP TABLE piece_occasions;
ALTER TABLE piece_occasions_new RENAME TO piece_occasions;
CREATE INDEX piece_occasions_occasion ON piece_occasions (occasion_id);

CREATE TABLE look_occasions_new (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  look_id INTEGER NOT NULL REFERENCES looks (id) ON DELETE CASCADE,
  occasion_id INTEGER NOT NULL REFERENCES occasions (id) ON DELETE CASCADE,
  PRIMARY KEY (look_id, occasion_id)
) STRICT;

INSERT INTO look_occasions_new (user_id, look_id, occasion_id)
  SELECT lo.user_id, lo.look_id, o.id
  FROM look_occasions lo JOIN occasions o ON o.user_id = lo.user_id AND o.name = lo.occasion;

DROP TABLE look_occasions;
ALTER TABLE look_occasions_new RENAME TO look_occasions;
CREATE INDEX look_occasions_occasion ON look_occasions (occasion_id);


-- 4. Caro's four, named as they show, with the line that explains each (onboarding step 5).
ALTER TABLE proposed_occasions ADD COLUMN description TEXT;

UPDATE proposed_occasions SET name = 'Office', description = 'Workdays with colleagues or clients.' WHERE name = 'office';
UPDATE proposed_occasions SET name = 'Working from home', description = 'Days at your own desk, calls included.' WHERE name = 'working from home';
UPDATE proposed_occasions SET name = 'Night out', description = 'Dinners, drinks and evenings out.' WHERE name = 'night out';
UPDATE proposed_occasions SET name = 'Day out', description = 'Weekends, errands and lunches with friends.' WHERE name = 'day out';
