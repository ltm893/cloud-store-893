-- seed-tax-exempt-backfill.sql — add tax_exempt to existing ADB deployments
--
-- Run in Database Actions SQL worksheet as ADMIN (F5 = Run Script).
-- Safe to re-run: adds column only when missing and recreates cart_view.

DECLARE
  col_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO col_count
  FROM user_tab_columns
  WHERE table_name = 'PRODUCTS' AND column_name = 'TAX_EXEMPT';

  IF col_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE products ADD (tax_exempt NUMBER(1) DEFAULT 0 NOT NULL)';
  END IF;
END;
/

UPDATE products
SET tax_exempt = 0
WHERE tax_exempt IS NULL OR tax_exempt NOT IN (0, 1);

CREATE OR REPLACE VIEW cart_view AS
  SELECT
    ci.id,
    ci.product_id,
    p.name,
    p.price,
    p.sale_price,
    p.tax_exempt,
    ci.quantity
  FROM cart_items ci
  JOIN products p ON p.id = ci.product_id;

SELECT 'tax_exempt column' AS section,
       COUNT(*) AS has_column
FROM user_tab_columns
WHERE table_name = 'PRODUCTS' AND column_name = 'TAX_EXEMPT';
