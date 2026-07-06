-- adjust-inventory-plus5.sql — add 5 units to retail stock for selected product IDs
--
-- Products (seed order): 7–9 coffee beans, 11 go cup, 15 hoodie.
-- Run: ./scripts/db/run-sql.sh scripts/db/adjust-inventory-plus5.sql

SET ECHO ON
SET FEEDBACK ON

-- Before
SELECT pi.product_id, p.name, pi.quantity_on_hand
FROM product_inventory pi
JOIN products p ON p.id = pi.product_id
WHERE pi.product_id IN (7, 8, 9, 11, 15)
ORDER BY pi.product_id;

UPDATE product_inventory
SET
  quantity_on_hand = quantity_on_hand + 5,
  updated_at = SYSTIMESTAMP
WHERE product_id IN (7, 8, 9, 11, 15);

COMMIT;

INSERT INTO inventory_movements (product_id, delta, quantity_after, reason, note)
SELECT
  product_id,
  5,
  quantity_on_hand,
  'adjust',
  'Manual +5 (adjust-inventory-plus5.sql)'
FROM product_inventory
WHERE product_id IN (7, 8, 9, 11, 15);

COMMIT;

-- After
SELECT pi.product_id, p.name, pi.quantity_on_hand
FROM product_inventory pi
JOIN products p ON p.id = pi.product_id
WHERE pi.product_id IN (7, 8, 9, 11, 15)
ORDER BY pi.product_id;
