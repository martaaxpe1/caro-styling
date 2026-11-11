-- 003: where members live, for onboarding steps 2 to 4 (PRD sections 5 and 9). Added in T4.
--
-- - cities: each city a member has chosen, from Open-Meteo's city search. Its id is the
--   city's number in GeoNames, the public list of places that search is built on.
-- - city_weather: the typical high and rain for each month of a city. A cache: it is looked
--   up once (Claude's memory, checked against Open-Meteo) and kept, so the next member in
--   the same city gets it at once and at no cost.
-- Both hold public facts about places, not anyone's data, so they have no user_id.

CREATE TABLE cities (
  id INTEGER PRIMARY KEY,               -- the GeoNames id, like 4164138 for Miami
  name TEXT NOT NULL,                   -- Miami
  region TEXT,                          -- Florida: the state or province, when there is one
  country TEXT NOT NULL,                -- two letters, like US
  latitude REAL NOT NULL,               -- below 0 is the southern hemisphere: seasons shift by six months
  longitude REAL NOT NULL,
  timezone TEXT,
  weather_source TEXT CHECK (weather_source IN ('claude', 'open-meteo')),  -- empty until looked up
  weather_checked INTEGER NOT NULL DEFAULT 0 CHECK (weather_checked IN (0, 1)),  -- 1 once compared with Open-Meteo
  weather_at TEXT,                      -- when the weather was looked up
  created_at TEXT NOT NULL
) STRICT;

-- Twelve rows per city once its weather is known.
CREATE TABLE city_weather (
  city_id INTEGER NOT NULL REFERENCES cities (id) ON DELETE CASCADE,
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  high_c REAL NOT NULL,                 -- typical daily high, °C
  rain_mm REAL NOT NULL,                -- typical rain in the month, mm
  PRIMARY KEY (city_id, month)
) STRICT;

-- The member's city, and the formats they confirmed in step 2. Empty dates and sizes mean
-- "as the country does it".
ALTER TABLE users ADD COLUMN city_id INTEGER REFERENCES cities (id);
ALTER TABLE users ADD COLUMN date_order TEXT CHECK (date_order IN ('day month', 'month day'));  -- 30 Oct or Oct 30
ALTER TABLE users ADD COLUMN size_system TEXT CHECK (size_system IN ('EU', 'US', 'UK', 'AU'));

-- The country a store's website was found for. After a member moves, a store found for the
-- old country keeps its website until the member confirms the new one, and the store search
-- skips it until then.
ALTER TABLE stores ADD COLUMN country TEXT;

-- Stores added before T4 (the seed) were found for their member's country.
UPDATE stores SET country = (SELECT country FROM users WHERE users.id = stores.user_id);
