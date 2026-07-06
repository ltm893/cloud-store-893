-- Backfill audit rows for adjust-inventory-plus5.sql (UPDATE committed before INSERT failed).
INSERT INTO inventory_movements (product_id, delta, quantity_after, reason, note)
SELECT
  product_id,
  5,
  quantity_on_hand,
  'adjust',
  'Manual +5 (adjust-inventory-plus5.sql)'
FROM product_inventory
WHERE product_id IN (7, 8, 9, 11, 15)
  AND NOT EXISTS (
    SELECT 1
    FROM inventory_movements im
    WHERE im.product_id = product_inventory.product_id
      AND im.delta = 5
      AND im.reason = 'adjust'
      AND im.note = 'Manual +5 (adjust-inventory-plus5.sql)'
  );

COMMIT;
