-- 008: look numbers are never reused (PRD sections 6 and 7). Added in T7.
--
-- Each member's looks are numbered No. 1, No. 2, ... A new look takes the number after the
-- highest one ever given, kept here, so after a delete "No. 7" still means only that look.

ALTER TABLE users ADD COLUMN looks_numbered INTEGER NOT NULL DEFAULT 0 CHECK (looks_numbered >= 0);

UPDATE users SET looks_numbered = (SELECT COALESCE(MAX(number), 0) FROM looks WHERE looks.user_id = users.id);
