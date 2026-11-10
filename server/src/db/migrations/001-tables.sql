-- 001: every table Caro starts with (PRD section 12).
--
-- How to read this file:
-- - Every table that holds a member's data has user_id, link tables included. Deleting a
--   member deletes all of it (ON DELETE CASCADE): that is how the 30-day clean-up works.
-- - Dates are text in UTC, like 2026-11-10T21:30:00Z. They come from src/lib/today.js,
--   never from SQLite's own clock, so DEV_TODAY works everywhere.
-- - Yes or no is 1 or 0. Prices are in cents: 49.95 is 4995.
-- - CHECK refuses any value not on its short list. Longer lists are tables of their own.
-- - STRICT refuses a value of the wrong type, like text in a number column.
-- - Never edit this file once it is committed. Change the database with a new numbered file.


-- The fixed lists, the same for every member. Their rows are in 002-lists.sql.

CREATE TABLE chapters (
  name TEXT PRIMARY KEY,                -- outerwear, knitwear, ...
  number INTEGER NOT NULL UNIQUE        -- 1 to 7, shown as 01 to 07
) STRICT;

-- Each kind belongs to one chapter and fills one slot on the styling table.
-- The slot also says what a piece counts as for the unlock rule: top, bottom, one-piece or shoes.
CREATE TABLE kinds (
  name TEXT PRIMARY KEY,                -- jumper, trench coat, ...
  chapter TEXT NOT NULL REFERENCES chapters (name),
  slot TEXT NOT NULL CHECK (slot IN ('outer layer', 'top', 'bottom', 'one-piece', 'shoes', 'bag', 'accessories')),
  position INTEGER NOT NULL
) STRICT;

CREATE TABLE colours (
  name TEXT PRIMARY KEY,
  position INTEGER NOT NULL
) STRICT;

CREATE TABLE patterns (
  name TEXT PRIMARY KEY,
  position INTEGER NOT NULL
) STRICT;

CREATE TABLE materials (
  name TEXT PRIMARY KEY,
  position INTEGER NOT NULL
) STRICT;

CREATE TABLE occasions (
  name TEXT PRIMARY KEY,
  position INTEGER NOT NULL
) STRICT;

-- Settings for the whole app, set by the admin. Always exactly one row.
CREATE TABLE settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  ai_monthly_allowance INTEGER NOT NULL CHECK (ai_monthly_allowance >= 0)  -- AI actions per member per month
) STRICT;


-- Accounts

CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  email TEXT NOT NULL UNIQUE CHECK (email = lower(trim(email))),
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin')),
  status TEXT NOT NULL DEFAULT 'onboarding' CHECK (status IN ('onboarding', 'active', 'removed')),
  onboarding_step INTEGER NOT NULL DEFAULT 1 CHECK (onboarding_step BETWEEN 1 AND 6),  -- where to resume
  city TEXT,
  country TEXT,                         -- two letters, like NL or US
  currency TEXT,                        -- three letters, like EUR or USD
  shops_womens INTEGER NOT NULL DEFAULT 0 CHECK (shops_womens IN (0, 1)),  -- the store sections
  shops_mens INTEGER NOT NULL DEFAULT 0 CHECK (shops_mens IN (0, 1)),      -- searched for this member,
  shops_unisex INTEGER NOT NULL DEFAULT 0 CHECK (shops_unisex IN (0, 1)),  -- none until they choose
  unlocked_at TEXT,                     -- when Looks and Get the look opened. Once set, never cleared.
  removed_at TEXT,
  created_at TEXT NOT NULL,
  last_active_at TEXT
) STRICT;

-- Invitations belong to the admin who sent them, not to the person invited.
CREATE TABLE invitations (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL CHECK (email = lower(trim(email))),
  invited_by INTEGER NOT NULL REFERENCES users (id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'cancelled', 'expired')),
  sent_at TEXT NOT NULL,
  expires_at TEXT NOT NULL              -- 14 days after sent
) STRICT;

-- Only one pending invitation per email.
CREATE UNIQUE INDEX invitations_one_pending ON invitations (email) WHERE status = 'pending';

-- Sign-in codes are kept by email, not by member: an invited person has no account
-- until their first sign-in.
CREATE TABLE login_codes (
  id INTEGER PRIMARY KEY,
  email TEXT NOT NULL CHECK (email = lower(trim(email))),
  code_hash TEXT NOT NULL,              -- never the code itself
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,             -- 15 minutes after created
  used_at TEXT
) STRICT;

CREATE INDEX login_codes_email ON login_codes (email);

CREATE TABLE sessions (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,      -- never the token itself
  created_at TEXT NOT NULL,
  last_used_at TEXT NOT NULL
) STRICT;


-- A member's set-up

CREATE TABLE seasons (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name TEXT NOT NULL,                   -- Autumn, Hot and rainy, ...: the member can rename it
  position INTEGER NOT NULL,
  UNIQUE (user_id, name)
) STRICT;

-- The season each month belongs to. A month is in one season at most, so seasons never overlap.
-- A member with no seasons has no rows here.
CREATE TABLE season_months (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  season_id INTEGER NOT NULL REFERENCES seasons (id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, month)
) STRICT;

CREATE TABLE stores (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name TEXT NOT NULL,                   -- as the store writes it, like COS
  domain TEXT,                          -- cos.com: the store search covers the whole website
  country_url TEXT,                     -- its shop for the member's country, like https://www.cos.com/en-nl/
  sells_online INTEGER NOT NULL CHECK (sells_online IN (0, 1)),  -- in the member's country
  position INTEGER NOT NULL,
  created_at TEXT NOT NULL
) STRICT;


-- The wardrobe

CREATE TABLE pieces (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'maybe')),  -- pending: in the review queue
  name TEXT,
  kind TEXT REFERENCES kinds (name),    -- the chapter and slot follow from the kind
  pattern TEXT REFERENCES patterns (name),
  material TEXT REFERENCES materials (name),
  warmth TEXT CHECK (warmth IN ('light', 'medium', 'warm')),
  formality TEXT CHECK (formality IN ('casual', 'smart casual', 'smart', 'formal')),
  brand TEXT,
  size TEXT,
  size_system TEXT,                     -- EU, US, ...: the same size differs by system
  price_cents INTEGER CHECK (price_cents >= 0),
  price_currency TEXT,
  notes TEXT,
  original_path TEXT NOT NULL,          -- photo files, inside DATA_DIR
  cutout_path TEXT,                     -- empty when nothing lifted: the app shows the photo itself
  thumb_path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  confirmed_at TEXT,
  CHECK (status = 'pending' OR (name IS NOT NULL AND kind IS NOT NULL))  -- confirmed needs a name and kind
) STRICT;

CREATE INDEX pieces_user ON pieces (user_id, status);

-- Up to three colours, as seen from the outside when worn. Position 1 is the main colour.
CREATE TABLE piece_colours (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  piece_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  colour TEXT NOT NULL REFERENCES colours (name),
  position INTEGER NOT NULL CHECK (position BETWEEN 1 AND 3),
  PRIMARY KEY (piece_id, position),
  UNIQUE (piece_id, colour)
) STRICT;

CREATE TABLE piece_occasions (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  piece_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  occasion TEXT NOT NULL REFERENCES occasions (name),
  PRIMARY KEY (piece_id, occasion)
) STRICT;

CREATE TABLE piece_seasons (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  piece_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  season_id INTEGER NOT NULL REFERENCES seasons (id) ON DELETE CASCADE,
  PRIMARY KEY (piece_id, season_id)
) STRICT;


-- Looks

CREATE TABLE looks (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  number INTEGER NOT NULL,              -- each member's looks are numbered 1, 2, 3, ...
  source TEXT NOT NULL CHECK (source IN ('built', 'photo', 'inspired')),
  note TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (user_id, number)
) STRICT;

CREATE INDEX looks_user ON looks (user_id);

CREATE TABLE look_pieces (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  look_id INTEGER NOT NULL REFERENCES looks (id) ON DELETE CASCADE,
  piece_id INTEGER NOT NULL REFERENCES pieces (id) ON DELETE CASCADE,
  slot TEXT NOT NULL CHECK (slot IN ('outer layer', 'top', 'bottom', 'one-piece', 'shoes', 'bag', 'accessories')),
  PRIMARY KEY (look_id, piece_id)
) STRICT;

-- One piece per slot, except accessories, which can hold several.
CREATE UNIQUE INDEX look_pieces_one_per_slot ON look_pieces (look_id, slot) WHERE slot <> 'accessories';

CREATE TABLE look_occasions (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  look_id INTEGER NOT NULL REFERENCES looks (id) ON DELETE CASCADE,
  occasion TEXT NOT NULL REFERENCES occasions (name),
  PRIMARY KEY (look_id, occasion)
) STRICT;

CREATE TABLE look_seasons (
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  look_id INTEGER NOT NULL REFERENCES looks (id) ON DELETE CASCADE,
  season_id INTEGER NOT NULL REFERENCES seasons (id) ON DELETE CASCADE,
  PRIMARY KEY (look_id, season_id)
) STRICT;

-- Photos of the member wearing a look.
CREATE TABLE look_photos (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  look_id INTEGER NOT NULL REFERENCES looks (id) ON DELETE CASCADE,
  photo_path TEXT NOT NULL,
  thumb_path TEXT NOT NULL,
  added_at TEXT NOT NULL
) STRICT;


-- Get the look

CREATE TABLE inspirations (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  photo_path TEXT NOT NULL,
  thumb_path TEXT NOT NULL,
  link TEXT,                            -- where it came from, like a Pinterest page
  note TEXT,
  created_at TEXT NOT NULL
) STRICT;

CREATE INDEX inspirations_user ON inspirations (user_id);

-- Each piece the AI described in an inspiration, and the member's piece it was compared with.
CREATE TABLE inspiration_pieces (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  inspiration_id INTEGER NOT NULL REFERENCES inspirations (id) ON DELETE CASCADE,
  number INTEGER NOT NULL,              -- the pin number on the photo
  description TEXT NOT NULL,            -- like "grey oversized blazer"
  kind TEXT REFERENCES kinds (name),
  matched_piece_id INTEGER REFERENCES pieces (id) ON DELETE SET NULL,  -- the match, or for a missing piece the nearest of that kind
  match TEXT NOT NULL CHECK (match IN ('yours', 'close', 'missing')),
  is_key INTEGER NOT NULL DEFAULT 0 CHECK (is_key IN (0, 1)),
  UNIQUE (inspiration_id, number)
) STRICT;

-- To find: missing pieces the member marked as key.
CREATE TABLE to_find (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  inspiration_piece_id INTEGER NOT NULL UNIQUE REFERENCES inspiration_pieces (id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'considering' CHECK (status IN ('considering', 'bought', 'dropped')),
  searched_at TEXT,                     -- the last Find it. Empty: not searched yet.
  created_at TEXT NOT NULL
) STRICT;

CREATE INDEX to_find_user ON to_find (user_id);

-- Products a store search found, kept with the date found, since stock and prices change.
CREATE TABLE store_results (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  to_find_id INTEGER NOT NULL REFERENCES to_find (id) ON DELETE CASCADE,
  store_id INTEGER NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price_cents INTEGER CHECK (price_cents >= 0),
  currency TEXT,
  url TEXT NOT NULL,
  image_url TEXT,
  found_at TEXT NOT NULL
) STRICT;


-- AI

-- One row per AI action, to count against the monthly allowance and to show the admin totals.
CREATE TABLE ai_usage (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('piece details', 'look from a photo', 'inspiration', 'store search', 'store website', 'your year')),
  created_at TEXT NOT NULL
) STRICT;

CREATE INDEX ai_usage_user ON ai_usage (user_id, created_at);
