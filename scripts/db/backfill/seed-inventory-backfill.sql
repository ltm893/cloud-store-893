-- seed-inventory-backfill.sql — fix empty product_inventory on an existing ADB
--
-- Run in Database Actions SQL worksheet as ADMIN (F5 = Run Script).
-- Safe to re-run: uses MERGE and only adds missing inventory rows.
--
-- Expected result: product_inventory row_count ≈ 11 (all retail SKUs; made coffee untracked).

-- ── 0. Ensure schema objects exist ────────────────────────────────────────────

DECLARE
  col_count NUMBER;
  tbl_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO col_count
  FROM user_tab_columns
  WHERE table_name = 'PRODUCTS' AND column_name = 'TRACK_INVENTORY';

  IF col_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE products ADD (track_inventory NUMBER(1) DEFAULT 0 NOT NULL)';
  END IF;

  SELECT COUNT(*) INTO tbl_count FROM user_tables WHERE table_name = 'PRODUCT_INVENTORY';
  IF tbl_count = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE product_inventory (
        product_id       NUMBER PRIMARY KEY REFERENCES products(id),
        quantity_on_hand NUMBER DEFAULT 0 NOT NULL,
        reorder_point    NUMBER DEFAULT 0 NOT NULL,
        updated_at       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT product_inventory_qty_nonneg CHECK (quantity_on_hand >= 0)
      )';
  END IF;
END;
/


-- ── 1. Diagnostics (read the result grid) ─────────────────────────────────────

SELECT 'products by type' AS section, product_type, track_inventory, COUNT(*) AS cnt
FROM products
GROUP BY product_type, track_inventory
ORDER BY product_type, track_inventory;

SELECT 'missing track_inventory column?' AS section,
       COUNT(*) AS has_column
FROM user_tab_columns
WHERE table_name = 'PRODUCTS' AND column_name = 'TRACK_INVENTORY';

SELECT 'product_inventory before' AS section, COUNT(*) AS row_count FROM product_inventory;


-- ── 2. Mark retail SKUs as tracked ──────────────────────────────────────────
-- Primary match: product_type from seed.sql
-- Fallback: Java Rocks retail barcodes (beans 101+, cups 201+, clothes 301+)

UPDATE products
SET track_inventory = 0
WHERE track_inventory IS NULL OR track_inventory NOT IN (0, 1);

UPDATE products
SET track_inventory = 1
WHERE product_type IN ('coffee beans', 'go cups', 'clothes')
   OR barcode LIKE '8720000001%'
   OR barcode LIKE '8720000002%'
   OR barcode LIKE '8720000003%';

UPDATE products
SET track_inventory = 0
WHERE barcode IN (
  '872000000001',
  '872000000002',
  '872000000003',
  '872000000004',
  '872000000005'
);


-- ── 3. Upsert inventory balances ──────────────────────────────────────────────

MERGE INTO product_inventory pi
USING (
  SELECT
    p.id AS product_id,
    CASE p.product_type
      WHEN 'coffee beans' THEN 30
      WHEN 'go cups' THEN 20
      WHEN 'clothes' THEN 10
      ELSE 15
    END AS quantity_on_hand,
    CASE p.product_type
      WHEN 'coffee beans' THEN 5
      WHEN 'go cups' THEN 3
      WHEN 'clothes' THEN 2
      ELSE 2
    END AS reorder_point
  FROM products p
  WHERE p.track_inventory = 1
) src
ON (pi.product_id = src.product_id)
WHEN MATCHED THEN
  UPDATE SET
    pi.quantity_on_hand = CASE WHEN pi.quantity_on_hand = 0 THEN src.quantity_on_hand ELSE pi.quantity_on_hand END,
    pi.reorder_point = src.reorder_point,
    pi.updated_at = SYSTIMESTAMP
WHEN NOT MATCHED THEN
  INSERT (product_id, quantity_on_hand, reorder_point, updated_at)
  VALUES (src.product_id, src.quantity_on_hand, src.reorder_point, SYSTIMESTAMP);


-- ── 4. Verify ─────────────────────────────────────────────────────────────────

SELECT 'tracked products' AS section, COUNT(*) AS cnt
FROM products WHERE track_inventory = 1;

SELECT 'product_inventory after' AS section, COUNT(*) AS row_count FROM product_inventory;

SELECT p.id, p.barcode, p.name, p.product_type, p.track_inventory,
       pi.quantity_on_hand, pi.reorder_point
FROM products p
LEFT JOIN product_inventory pi ON pi.product_id = p.id
ORDER BY p.id;

COMMIT;
