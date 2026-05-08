-- seed.sql — Database setup for cloud-store-893
--
-- Run this in Database Actions SQL Worksheet as ADMIN:
--   OCI Console → Oracle Database → Autonomous Database
--   → adb-cloud-store-893 → Database Actions → SQL
--
-- Paste the entire file and click Run Script (F5).
-- All steps are safe to re-run (CREATE OR REPLACE / DROP IF EXISTS).


-- ── 0. Cleanup (safe to re-run) ─────────────────────────────────────────────
-- Drop objects in reverse dependency order so re-runs start clean.

BEGIN EXECUTE IMMEDIATE 'DROP VIEW cart_view';   EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE sale_items'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE sales';      EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE cart_items'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE products';   EXCEPTION WHEN OTHERS THEN NULL; END;
/


-- ── 1. PRODUCTS table ─────────────────────────────────────────────────────────

CREATE TABLE products (
  id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barcode VARCHAR2(32)   NOT NULL UNIQUE,
  name    VARCHAR2(200)  NOT NULL,
  price   NUMBER(10, 2)  NOT NULL
);


-- ── 2. CART_ITEMS table ───────────────────────────────────────────────────────

CREATE TABLE cart_items (
  id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id NUMBER        NOT NULL REFERENCES products(id),
  quantity   NUMBER        DEFAULT 1 NOT NULL
);

-- ── 3. SALES table ────────────────────────────────────────────────────────────

CREATE TABLE sales (
  id             NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number   VARCHAR2(64)   NOT NULL UNIQUE,
  total          NUMBER(10, 2)  NOT NULL,
  payment_method VARCHAR2(50)   NOT NULL,
  created_at     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
);


-- ── 4. SALE_ITEMS table ───────────────────────────────────────────────────────

CREATE TABLE sale_items (
  id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number VARCHAR2(64)   NOT NULL,
  product_id   NUMBER         NOT NULL REFERENCES products(id),
  quantity     NUMBER         NOT NULL,
  unit_price   NUMBER(10, 2)  NOT NULL,
  line_total   NUMBER(10, 2)  NOT NULL
);


-- ── 5. CART_VIEW ──────────────────────────────────────────────────────────────
-- Joins cart_items + products so the app can read name/price with one ORDS call.
-- Returns: id (cart_items.id used for DELETE), product_id, name, price, quantity

CREATE OR REPLACE VIEW cart_view AS
  SELECT
    ci.id,
    ci.product_id,
    p.name,
    p.price,
    ci.quantity
  FROM cart_items ci
  JOIN products p ON p.id = ci.product_id;


-- ── 6. Enable ORDS on the ADMIN schema ───────────────────────────────────────
-- This maps /ords/admin/... to this schema.
-- p_url_mapping_pattern must match the path in your ORDS_BASE_URL.

BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => 'ADMIN',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'admin',
    p_auto_rest_auth      => FALSE
  );
  COMMIT;
END;
/


-- ── 7. Enable ORDS on PRODUCTS table ─────────────────────────────────────────
-- Exposes: GET /ords/admin/products/
--          POST /ords/admin/products/
--          PUT /ords/admin/products/:id
--          DELETE /ords/admin/products/:id

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'PRODUCTS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'products',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 8. Enable ORDS on CART_ITEMS table ───────────────────────────────────────
-- Exposes: GET /ords/admin/cart_items/
--          POST /ords/admin/cart_items/
--          PUT /ords/admin/cart_items/:id
--          DELETE /ords/admin/cart_items/:id

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'CART_ITEMS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'cart_items',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 9. Enable ORDS on CART_VIEW ───────────────────────────────────────────────
-- Exposes: GET /ords/admin/cart_view/
-- Read-only (views don't support POST/PUT/DELETE via ORDS)

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'CART_VIEW',
    p_object_type   => 'VIEW',
    p_object_alias  => 'cart_view',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

-- ── 10. Enable ORDS on SALES table ────────────────────────────────────────────
-- Exposes: GET /ords/admin/sales/
--          POST /ords/admin/sales/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'SALES',
    p_object_type   => 'TABLE',
    p_object_alias  => 'sales',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

-- ── 11. Enable ORDS on SALE_ITEMS table ───────────────────────────────────────
-- Exposes: GET /ords/admin/sale_items/
--          POST /ords/admin/sale_items/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'SALE_ITEMS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'sale_items',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 12. Sample products ───────────────────────────────────────────────────────

INSERT INTO products (barcode, name, price) VALUES ('100000000001', 'OCI Foundations Study Guide',  29.99);
INSERT INTO products (barcode, name, price) VALUES ('100000000002', 'Terraform on OCI T-Shirt',     24.99);
INSERT INTO products (barcode, name, price) VALUES ('100000000003', 'Cloud Architecture Poster',    14.99);
INSERT INTO products (barcode, name, price) VALUES ('100000000004', 'Autonomous Database Mug',       9.99);
INSERT INTO products (barcode, name, price) VALUES ('100000000005', 'Always Free Tier Sticker Pack', 4.99);

COMMIT;


-- ── Verify ────────────────────────────────────────────────────────────────────

SELECT 'products'  AS tbl, COUNT(*) AS row_count FROM products
UNION ALL
SELECT 'cart_items', COUNT(*) FROM cart_items
UNION ALL
SELECT 'sales', COUNT(*) FROM sales
UNION ALL
SELECT 'sale_items', COUNT(*) FROM sale_items;

exit
