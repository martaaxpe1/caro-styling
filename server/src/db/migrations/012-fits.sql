-- 012: doesn't fit yet (PRD sections 6 and 8). Added in T13.
--
-- A piece the member keeps and wants to be reminded of, but that does not fit now. 1: it fits,
-- as every piece does until the member says otherwise. 0: it doesn't fit yet. Apart from maybe:
-- a piece can be both.

ALTER TABLE pieces ADD COLUMN fits INTEGER NOT NULL DEFAULT 1 CHECK (fits IN (0, 1));
