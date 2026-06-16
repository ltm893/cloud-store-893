-- seed.sql — Database setup for cloud-store-893
--
-- Do not run this file directly with bash.
-- Use ./scripts/reset-db.sh or run it in Database Actions / SQLcl as ADMIN.
--
-- Run this in Database Actions SQL Worksheet as ADMIN:
--   OCI Console → Oracle Database → Autonomous Database
--   → adb-cloud-store-893 → Database Actions → SQL
--
-- Paste the entire file and click Run Script (F5).
-- All steps are safe to re-run (CREATE OR REPLACE / DROP IF EXISTS).


-- ── 0. Cleanup (safe to re-run) ─────────────────────────────────────────────
-- Drop objects in reverse dependency order so re-runs start clean.

BEGIN EXECUTE IMMEDIATE 'DROP VIEW inventory_status_view'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW cart_view';   EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE inventory_movements'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE inventory_consumption_rules'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE product_inventory'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE bulk_inventory'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE sale_payments'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE sale_items'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE sales';      EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE cart_items'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE products';   EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE till_close_approvals'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE tills'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE pos_sessions'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE till_open_approvals'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
-- Legacy table names (pre pos_sessions / tills rename)
BEGIN EXECUTE IMMEDIATE 'DROP TABLE register_shift_closes'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE register_shifts'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE login_approval_requests'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE customers';  EXCEPTION WHEN OTHERS THEN NULL; END;
/


-- ── 1. PRODUCTS table ─────────────────────────────────────────────────────────

CREATE TABLE products (
  id               NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barcode          VARCHAR2(32)   NOT NULL UNIQUE,
  name             VARCHAR2(200)  NOT NULL,
  product_type     VARCHAR2(50)   NOT NULL,
  manufacturer     VARCHAR2(200)  NOT NULL,
  price            NUMBER(10, 2)  NOT NULL,
  sale_price       NUMBER(10, 2),
  track_inventory  NUMBER(1)      DEFAULT 0 NOT NULL
);


-- ── 1b. PRODUCT_INVENTORY table ───────────────────────────────────────────────
-- One balance row per tracked SKU. Admins see exact counts; POS uses in/out-of-stock only.

CREATE TABLE product_inventory (
  product_id       NUMBER PRIMARY KEY REFERENCES products(id),
  quantity_on_hand NUMBER DEFAULT 0 NOT NULL,
  reorder_point    NUMBER DEFAULT 0 NOT NULL,
  updated_at       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT product_inventory_qty_nonneg CHECK (quantity_on_hand >= 0)
);


-- ── 1c. BULK_INVENTORY (kitchen stock — oz/lb, not sold at POS) ───────────────

CREATE TABLE bulk_inventory (
  sku_key           VARCHAR2(50) PRIMARY KEY,
  name              VARCHAR2(200) NOT NULL,
  quantity_on_hand  NUMBER(12, 3) DEFAULT 0 NOT NULL,
  unit              VARCHAR2(20)  DEFAULT 'oz' NOT NULL,
  reorder_point     NUMBER(12, 3) DEFAULT 0 NOT NULL,
  updated_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT bulk_inventory_qty_nonneg CHECK (quantity_on_hand >= 0)
);


-- ── 1d. INVENTORY_CONSUMPTION_RULES (product_type → bulk depletion) ───────────

CREATE TABLE inventory_consumption_rules (
  product_type      VARCHAR2(50) PRIMARY KEY,
  bulk_sku_key      VARCHAR2(50) NOT NULL REFERENCES bulk_inventory(sku_key),
  quantity_per_unit NUMBER(12, 3) NOT NULL,
  unit              VARCHAR2(20)  NOT NULL
);


-- ── 1e. INVENTORY_MOVEMENTS table (audit ledger) ─────────────────────────────

CREATE TABLE inventory_movements (
  id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id      NUMBER REFERENCES products(id),
  bulk_sku_key    VARCHAR2(50) REFERENCES bulk_inventory(sku_key),
  delta           NUMBER NOT NULL,
  quantity_after  NUMBER NOT NULL,
  reason          VARCHAR2(50) NOT NULL,
  order_number    VARCHAR2(64),
  note            VARCHAR2(500),
  created_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT inventory_movements_target_ck CHECK (
    (product_id IS NOT NULL AND bulk_sku_key IS NULL)
    OR (product_id IS NULL AND bulk_sku_key IS NOT NULL)
  )
);


-- ── 2. CUSTOMERS table (any linked customer gets 10% pre-tax discount) ─────────

CREATE TABLE customers (
  id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name          VARCHAR2(200)  NOT NULL,
  email         VARCHAR2(200),
  phone         VARCHAR2(50),
  address_line1 VARCHAR2(200),
  address_line2 VARCHAR2(200),
  city          VARCHAR2(100),
  state         VARCHAR2(50),
  postal_code   VARCHAR2(20),
  card_fake     VARCHAR2(64),
  member_code   VARCHAR2(32)
);


-- ── 3. CART_ITEMS table ───────────────────────────────────────────────────────

CREATE TABLE cart_items (
  id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id NUMBER        NOT NULL REFERENCES products(id),
  quantity   NUMBER        DEFAULT 1 NOT NULL
);

-- ── 4. SALES table ────────────────────────────────────────────────────────────

CREATE TABLE sales (
  id                       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number             VARCHAR2(64)   NOT NULL UNIQUE,
  total                    NUMBER(10, 2)  NOT NULL,
  register_total           NUMBER(10, 2),
  cash_due                 NUMBER(10, 2),
  payment_method           VARCHAR2(50)   NOT NULL,
  customer_id              NUMBER         REFERENCES customers(id),
  subtotal_pre_member      NUMBER(10, 2)  NOT NULL,
  member_discount_pre_tax  NUMBER(10, 2)  DEFAULT 0 NOT NULL,
  linked_893               NUMBER(1)      DEFAULT 0 NOT NULL,
  till_id                  NUMBER,
  created_at               TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
);


-- ── 5. SALE_ITEMS table ───────────────────────────────────────────────────────

CREATE TABLE sale_items (
  id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number VARCHAR2(64)   NOT NULL,
  product_id   NUMBER         NOT NULL REFERENCES products(id),
  quantity     NUMBER         NOT NULL,
  unit_price   NUMBER(10, 2)  NOT NULL,
  line_total   NUMBER(10, 2)  NOT NULL
);


-- ── 6. SALE_PAYMENTS table ────────────────────────────────────────────────────

CREATE TABLE sale_payments (
  id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number    VARCHAR2(64)   NOT NULL REFERENCES sales(order_number),
  sequence_number NUMBER         NOT NULL,
  payment_method  VARCHAR2(50)   NOT NULL,
  amount          NUMBER(10, 2)  NOT NULL,
  tendered_amount NUMBER(10, 2),
  change_given    NUMBER(10, 2),
  created_at      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
);


-- ── 7. POS_SESSIONS (tablet OIDC wrapper — parent of till work) ───────────────

CREATE TABLE pos_sessions (
  id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  register_id   VARCHAR2(64),
  cashier_sub   VARCHAR2(256)  NOT NULL,
  cashier_email VARCHAR2(256),
  status        VARCHAR2(20)   NOT NULL,
  started_at    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  ended_at      TIMESTAMP
);

CREATE INDEX pos_sessions_register_idx
  ON pos_sessions (register_id, status, started_at);

CREATE INDEX pos_sessions_cashier_idx
  ON pos_sessions (cashier_sub, status, started_at);


-- ── 7b. TILL_OPEN_APPROVALS (supervisor approves till open) ───────────────────

CREATE TABLE till_open_approvals (
  id                     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_token          VARCHAR2(64)   NOT NULL UNIQUE,
  status                 VARCHAR2(20)   NOT NULL,
  pos_session_id         NUMBER         REFERENCES pos_sessions(id),
  cashier_sub            VARCHAR2(256)  NOT NULL,
  cashier_email          VARCHAR2(256),
  cashier_name           VARCHAR2(200),
  register_id            VARCHAR2(64),
  client_kind            VARCHAR2(20),
  requested_at           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  expires_at             TIMESTAMP      NOT NULL,
  resolved_at            TIMESTAMP,
  resolved_by_sub        VARCHAR2(256),
  resolved_by_email      VARCHAR2(256),
  deny_reason            VARCHAR2(500),
  till_type              VARCHAR2(20),
  expected_opening_float NUMBER(10, 2),
  opening_counted_float  NUMBER(10, 2),
  opening_variance       NUMBER(10, 2),
  opening_denominations  CLOB,
  till_submitted_at      TIMESTAMP
);

CREATE INDEX till_open_approvals_status_idx
  ON till_open_approvals (status, expires_at);


-- ── 7c. TILLS (supervised drawer session — history per open→close) ───────────

CREATE TABLE tills (
  id                     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pos_session_id         NUMBER         NOT NULL REFERENCES pos_sessions(id),
  register_id            VARCHAR2(64),
  cashier_sub            VARCHAR2(256)  NOT NULL,
  cashier_email          VARCHAR2(256),
  till_type              VARCHAR2(20)   NOT NULL,
  expected_opening_float NUMBER(10, 2),
  opening_counted_float  NUMBER(10, 2),
  opening_denominations  CLOB,
  opening_variance       NUMBER(10, 2),
  open_approval_token    VARCHAR2(64),
  cash_sales             NUMBER(10, 2)  DEFAULT 0 NOT NULL,
  credit_sales           NUMBER(10, 2)  DEFAULT 0 NOT NULL,
  opened_at              TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  closed_at              TIMESTAMP,
  status                 VARCHAR2(20)   NOT NULL
);

CREATE INDEX tills_cashier_idx
  ON tills (cashier_sub, status, opened_at);

CREATE INDEX tills_register_idx
  ON tills (register_id, status, opened_at);


-- ── 7d. TILL_CLOSE_APPROVALS (supervisor approves till close / EOD) ──────────

CREATE TABLE till_close_approvals (
  id                     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  close_token            VARCHAR2(64)   NOT NULL UNIQUE,
  till_id                NUMBER         NOT NULL REFERENCES tills(id),
  register_id            VARCHAR2(64),
  cashier_sub            VARCHAR2(256)  NOT NULL,
  cashier_email          VARCHAR2(256),
  cashier_name           VARCHAR2(200),
  till_type              VARCHAR2(20)   NOT NULL,
  expected_close_float   NUMBER(10, 2),
  counted_close_float    NUMBER(10, 2),
  close_variance         NUMBER(10, 2),
  close_denominations    CLOB,
  cash_sales_total       NUMBER(10, 2),
  change_given_total     NUMBER(10, 2),
  opening_counted_float  NUMBER(10, 2),
  status                 VARCHAR2(20)   NOT NULL,
  requested_at           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  expires_at             TIMESTAMP      NOT NULL,
  resolved_at            TIMESTAMP,
  resolved_by_sub        VARCHAR2(256),
  resolved_by_email      VARCHAR2(256),
  deny_reason            VARCHAR2(500)
);

CREATE INDEX till_close_approvals_status_idx
  ON till_close_approvals (status, expires_at);


-- ── 8. CART_VIEW ──────────────────────────────────────────────────────────────
-- Joins cart_items + products: list price, optional sale_price, quantity

CREATE OR REPLACE VIEW cart_view AS
  SELECT
    ci.id,
    ci.product_id,
    p.name,
    p.price,
    p.sale_price,
    ci.quantity
  FROM cart_items ci
  JOIN products p ON p.id = ci.product_id;


-- ── 8b. INVENTORY_STATUS_VIEW (admin read-only dashboard) ────────────────────

CREATE OR REPLACE VIEW inventory_status_view AS
  SELECT
    p.id            AS product_id,
    p.barcode,
    p.name,
    p.product_type,
    pi.quantity_on_hand,
    pi.reorder_point,
    CASE WHEN pi.quantity_on_hand <= pi.reorder_point THEN 1 ELSE 0 END AS low_stock
  FROM products p
  JOIN product_inventory pi ON pi.product_id = p.id
  WHERE p.track_inventory = 1;


-- ── 9. Enable ORDS on the ADMIN schema ───────────────────────────────────────

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


-- ── 10. Enable ORDS on PRODUCTS table ────────────────────────────────────────

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


-- ── 11. Enable ORDS on CUSTOMERS table ───────────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'CUSTOMERS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'customers',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 12. Enable ORDS on CART_ITEMS table ──────────────────────────────────────

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


-- ── 13. Enable ORDS on CART_VIEW ───────────────────────────────────────────────

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


-- ── 14. Enable ORDS on SALES table ───────────────────────────────────────────

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

-- ── 15. Enable ORDS on SALE_ITEMS table ──────────────────────────────────────

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


-- ── 16. Enable ORDS on SALE_PAYMENTS table ───────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'SALE_PAYMENTS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'sale_payments',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 17. Enable ORDS on PRODUCT_INVENTORY table ───────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'PRODUCT_INVENTORY',
    p_object_type   => 'TABLE',
    p_object_alias  => 'product_inventory',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 18. Enable ORDS on INVENTORY_MOVEMENTS table ─────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'INVENTORY_MOVEMENTS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'inventory_movements',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 19. Enable ORDS on INVENTORY_STATUS_VIEW ─────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'INVENTORY_STATUS_VIEW',
    p_object_type   => 'VIEW',
    p_object_alias  => 'inventory_status_view',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 20. Enable ORDS on BULK_INVENTORY table ─────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'BULK_INVENTORY',
    p_object_type   => 'TABLE',
    p_object_alias  => 'bulk_inventory',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 21. Enable ORDS on INVENTORY_CONSUMPTION_RULES table ────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'INVENTORY_CONSUMPTION_RULES',
    p_object_type   => 'TABLE',
    p_object_alias  => 'inventory_consumption_rules',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 22. Enable ORDS on TILL_OPEN_APPROVALS table ─────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'TILL_OPEN_APPROVALS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'till_open_approvals',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 22b. Enable ORDS on POS_SESSIONS table ───────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'POS_SESSIONS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'pos_sessions',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 22c. Enable ORDS on TILLS table ──────────────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'TILLS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'tills',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 22d. Enable ORDS on TILL_CLOSE_APPROVALS table ─────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'TILL_CLOSE_APPROVALS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'till_close_approvals',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 23. Sample products — Java Rocks (coffee store) ───────────────────────────

-- Made coffee (bar)
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000001', 'Java Rocks House Drip 12oz', 'made coffee', 'Java Rocks Bar', 3.75, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000002', 'Java Rocks Latte 16oz', 'made coffee', 'Java Rocks Bar', 5.50, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000003', 'Java Rocks Cappuccino 12oz', 'made coffee', 'Java Rocks Bar', 5.25, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000004', 'Java Rocks Cold Brew 16oz', 'made coffee', 'Java Rocks Bar', 4.95, 4.25);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000005', 'Java Rocks Double Espresso', 'made coffee', 'Java Rocks Bar', 3.50, NULL);

-- Coffee beans (retail bags)
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000101', 'Java Rocks Colombia Supremo 12oz', 'coffee beans', 'Java Rocks Roastery', 16.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000102', 'Java Rocks Ethiopia Yirgacheffe 12oz', 'coffee beans', 'Java Rocks Roastery', 18.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000103', 'Java Rocks Espresso Roast 1lb', 'coffee beans', 'Java Rocks Roastery', 17.49, 15.99);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000104', 'Java Rocks Decaf Swiss Water 12oz', 'coffee beans', 'Swiss Water Process Co.', 15.99, NULL);

-- Branded go cups
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000201', 'Java Rocks 16oz Travel Tumbler', 'go cups', 'Pacific Drinkware Co.', 12.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000202', 'Java Rocks 20oz Go Cup', 'go cups', 'Pacific Drinkware Co.', 14.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000203', 'Java Rocks 24oz Cold Cup', 'go cups', 'Evergreen Reusables', 11.99, 9.99);

-- Clothes
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000301', 'Java Rocks Logo Tee — Navy', 'clothes', 'Bella+Canvas', 24.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000302', 'Java Rocks Logo Tee — Black', 'clothes', 'Bella+Canvas', 24.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000303', 'Java Rocks Hoodie — Charcoal', 'clothes', 'Independent Trading Co.', 49.99, NULL);
INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES ('872000000304', 'Java Rocks Barista Apron', 'clothes', 'Chef Works', 29.99, NULL);

-- ── 24. Inventory for retail SKUs (made coffee uses bulk beans, not shelf stock) ─

INSERT INTO bulk_inventory (sku_key, name, quantity_on_hand, unit, reorder_point)
VALUES ('kitchen_beans', 'Kitchen bulk coffee beans', 8000, 'oz', 500);

INSERT INTO inventory_consumption_rules (product_type, bulk_sku_key, quantity_per_unit, unit)
VALUES ('made coffee', 'kitchen_beans', 1.5, 'oz');

-- ── 25. Retail product_inventory ──────────────────────────────────────────────

UPDATE products
SET track_inventory = 1
WHERE product_type IN ('coffee beans', 'go cups', 'clothes');

INSERT INTO product_inventory (product_id, quantity_on_hand, reorder_point)
SELECT
  p.id,
  CASE p.product_type
    WHEN 'coffee beans' THEN 30
    WHEN 'go cups' THEN 20
    WHEN 'clothes' THEN 10
    ELSE 0
  END,
  CASE p.product_type
    WHEN 'coffee beans' THEN 5
    WHEN 'go cups' THEN 3
    WHEN 'clothes' THEN 2
    ELSE 0
  END
FROM products p
WHERE p.track_inventory = 1;


-- ── 26. Sample customers ───────────────────────────────────────────────────────

INSERT INTO customers (name, email, phone, address_line1, city, state, postal_code, card_fake, member_code)
VALUES (
  'Alex Rivera',
  'alex.rivera@example.com',
  '555-010-8720',
  '42 Roaster Row',
  'Portland',
  'OR',
  '97209',
  '4532015112830366',
  'JR-893'
);

INSERT INTO customers (name, email, phone, address_line1, city, state, postal_code, card_fake, member_code)
VALUES (
  'Jordan Guest',
  'jordan@example.com',
  '555-010-0001',
  '100 Public Rd',
  'Portland',
  'OR',
  '97201',
  '4111111111111111',
  NULL
);

COMMIT;


-- ── Verify ────────────────────────────────────────────────────────────────────

SELECT 'products'  AS tbl, COUNT(*) AS row_count FROM products
UNION ALL
SELECT 'product_inventory', COUNT(*) FROM product_inventory
UNION ALL
SELECT 'inventory_movements', COUNT(*) FROM inventory_movements
UNION ALL
SELECT 'bulk_inventory', COUNT(*) FROM bulk_inventory
UNION ALL
SELECT 'inventory_consumption_rules', COUNT(*) FROM inventory_consumption_rules
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'cart_items', COUNT(*) FROM cart_items
UNION ALL
SELECT 'sales', COUNT(*) FROM sales
UNION ALL
SELECT 'sale_items', COUNT(*) FROM sale_items
UNION ALL
SELECT 'sale_payments', COUNT(*) FROM sale_payments
UNION ALL
SELECT 'till_open_approvals', COUNT(*) FROM till_open_approvals
UNION ALL
SELECT 'pos_sessions', COUNT(*) FROM pos_sessions
UNION ALL
SELECT 'tills', COUNT(*) FROM tills
UNION ALL
SELECT 'till_close_approvals', COUNT(*) FROM till_close_approvals;

exit
