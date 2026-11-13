-- 010: Find it and To find (PRD sections 7 and 8, screen S11). Added in T11.
--
-- The store search for a key piece runs in the background (src/jobs/search-queue.js).
-- search_status says how far the last one got:
-- - empty: not searched yet
-- - searching: waiting for Claude
-- - done: the products are in store_results ("nothing found" is done with none)
-- - failed: Claude could not answer; the member can search again
ALTER TABLE to_find ADD COLUMN search_status TEXT CHECK (search_status IN ('searching', 'done', 'failed'));
-- Why a search failed, in words the app can show (like the allowance message).
ALTER TABLE to_find ADD COLUMN search_message TEXT;
-- The piece added to the edit when the member marked a product as bought.
ALTER TABLE to_find ADD COLUMN piece_id INTEGER REFERENCES pieces (id) ON DELETE SET NULL;

CREATE INDEX to_find_searching ON to_find (search_status) WHERE search_status = 'searching';

-- The member's choice on a product: kept (swiped right) or discarded (swiped left).
-- Empty: not decided yet. Search again replaces the undecided ones and keeps the kept ones.
ALTER TABLE store_results ADD COLUMN decision TEXT CHECK (decision IN ('kept', 'discarded'));

CREATE INDEX store_results_to_find ON store_results (to_find_id);

-- A piece added from a store's picture (Bought). Its page says to retake it when it arrives.
-- Retake clears it.
ALTER TABLE pieces ADD COLUMN store_photo TEXT;  -- the store's name, like COS
