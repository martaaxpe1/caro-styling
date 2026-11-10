-- 002: the fixed lists, the same for every member (PRD sections 6, 8 and 10).
-- They start from server/spike/lib/categories.js. Dresses and jumpsuits fill the one-piece slot.

INSERT INTO chapters (number, name) VALUES
  (1, 'outerwear'),
  (2, 'knitwear'),
  (3, 'tops'),
  (4, 'trousers'),
  (5, 'dresses and skirts'),
  (6, 'shoes'),
  (7, 'accessories');

INSERT INTO kinds (position, name, chapter, slot) VALUES
  (1, 'coat', 'outerwear', 'outer layer'),
  (2, 'trench coat', 'outerwear', 'outer layer'),
  (3, 'puffer jacket', 'outerwear', 'outer layer'),
  (4, 'jacket', 'outerwear', 'outer layer'),
  (5, 'leather jacket', 'outerwear', 'outer layer'),
  (6, 'denim jacket', 'outerwear', 'outer layer'),
  (7, 'blazer', 'outerwear', 'outer layer'),
  (8, 'gilet', 'outerwear', 'outer layer'),

  (9, 'jumper', 'knitwear', 'top'),
  (10, 'cardigan', 'knitwear', 'top'),
  (11, 'knitted vest', 'knitwear', 'top'),
  (12, 'knitted top', 'knitwear', 'top'),
  (13, 'sweatshirt', 'knitwear', 'top'),
  (14, 'hoodie', 'knitwear', 'top'),

  (15, 'shirt', 'tops', 'top'),
  (16, 'blouse', 'tops', 'top'),
  (17, 't-shirt', 'tops', 'top'),
  (18, 'long-sleeved top', 'tops', 'top'),
  (19, 'tank top', 'tops', 'top'),
  (20, 'bodysuit', 'tops', 'top'),

  (21, 'trousers', 'trousers', 'bottom'),
  (22, 'jeans', 'trousers', 'bottom'),
  (23, 'shorts', 'trousers', 'bottom'),
  (24, 'leggings', 'trousers', 'bottom'),

  (25, 'dress', 'dresses and skirts', 'one-piece'),
  (26, 'jumpsuit', 'dresses and skirts', 'one-piece'),
  (27, 'skirt', 'dresses and skirts', 'bottom'),

  (28, 'trainers', 'shoes', 'shoes'),
  (29, 'boots', 'shoes', 'shoes'),
  (30, 'ankle boots', 'shoes', 'shoes'),
  (31, 'loafers', 'shoes', 'shoes'),
  (32, 'ballet flats', 'shoes', 'shoes'),
  (33, 'heels', 'shoes', 'shoes'),
  (34, 'sandals', 'shoes', 'shoes'),
  (35, 'mules', 'shoes', 'shoes'),

  (36, 'bag', 'accessories', 'bag'),
  (37, 'belt', 'accessories', 'accessories'),
  (38, 'scarf', 'accessories', 'accessories'),
  (39, 'hat', 'accessories', 'accessories'),
  (40, 'sunglasses', 'accessories', 'accessories'),
  (41, 'jewellery', 'accessories', 'accessories');

INSERT INTO colours (position, name) VALUES
  (1, 'black'),
  (2, 'white'),
  (3, 'cream'),
  (4, 'beige'),
  (5, 'camel'),
  (6, 'brown'),
  (7, 'grey'),
  (8, 'navy'),
  (9, 'blue'),
  (10, 'light blue'),
  (11, 'green'),
  (12, 'olive'),
  (13, 'red'),
  (14, 'burgundy'),
  (15, 'pink'),
  (16, 'terracotta'),
  (17, 'orange'),
  (18, 'yellow'),
  (19, 'purple'),
  (20, 'silver'),
  (21, 'gold');

INSERT INTO patterns (position, name) VALUES
  (1, 'plain'),
  (2, 'striped'),
  (3, 'checked'),
  (4, 'floral'),
  (5, 'polka dot'),
  (6, 'animal print'),
  (7, 'graphic'),
  (8, 'other pattern');

INSERT INTO materials (position, name) VALUES
  (1, 'cotton'),
  (2, 'linen'),
  (3, 'wool'),
  (4, 'cashmere'),
  (5, 'silk'),
  (6, 'satin'),
  (7, 'denim'),
  (8, 'leather'),
  (9, 'suede'),
  (10, 'faux leather'),
  (11, 'viscose'),
  (12, 'polyester'),
  (13, 'nylon'),
  (14, 'canvas'),
  (15, 'straw'),
  (16, 'metal'),
  (17, 'not sure');

INSERT INTO occasions (position, name) VALUES
  (1, 'office'),
  (2, 'working from home'),
  (3, 'night out'),
  (4, 'day out');

-- The monthly AI allowance starts at 300 actions per member (PRD section 10).
INSERT INTO settings (id, ai_monthly_allowance) VALUES (1, 300);
