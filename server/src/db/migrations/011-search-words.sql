-- 011: the words Find it searches with (PRD section 8, S11). Added in T11, after Marta's test.
--
-- Empty: Caro's own description of the piece and its shape, like "Black crossbody bag, small,
-- slim strap". When nothing is found, the member can change the words and search again.
ALTER TABLE to_find ADD COLUMN search_words TEXT;
