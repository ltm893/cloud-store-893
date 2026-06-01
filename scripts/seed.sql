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

BEGIN EXECUTE IMMEDIATE 'DROP VIEW cart_view';   EXCEPTION WHEN OTHERS THEN NULL; END;
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
BEGIN EXECUTE IMMEDIATE 'DROP TABLE login_approval_requests'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE customers';  EXCEPTION WHEN OTHERS THEN NULL; END;
/


-- ── 1. PRODUCTS table ─────────────────────────────────────────────────────────

CREATE TABLE products (
  id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barcode      VARCHAR2(32)   NOT NULL UNIQUE,
  name         VARCHAR2(200)  NOT NULL,
  product_type VARCHAR2(50)   NOT NULL,
  manufacturer VARCHAR2(200)  NOT NULL,
  price        NUMBER(10, 2)  NOT NULL,
  sale_price   NUMBER(10, 2)
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
  payment_method           VARCHAR2(50)   NOT NULL,
  customer_id              NUMBER         REFERENCES customers(id),
  subtotal_pre_member      NUMBER(10, 2)  NOT NULL,
  member_discount_pre_tax  NUMBER(10, 2)  DEFAULT 0 NOT NULL,
  linked_893               NUMBER(1)      DEFAULT 0 NOT NULL,
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


-- ── 7. LOGIN_APPROVAL_REQUESTS (Model B: IdP cashier + supervisor approval) ───

CREATE TABLE login_approval_requests (
  id                NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_token     VARCHAR2(64)   NOT NULL UNIQUE,
  status            VARCHAR2(20)   NOT NULL,
  cashier_sub       VARCHAR2(256)  NOT NULL,
  cashier_email     VARCHAR2(256),
  cashier_name      VARCHAR2(200),
  register_id       VARCHAR2(64),
  client_kind       VARCHAR2(20),
  requested_at      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  expires_at        TIMESTAMP      NOT NULL,
  resolved_at       TIMESTAMP,
  resolved_by_sub   VARCHAR2(256),
  resolved_by_email VARCHAR2(256),
  deny_reason       VARCHAR2(500)
);

CREATE INDEX login_approval_requests_status_idx
  ON login_approval_requests (status, expires_at);


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


-- ── 17. Enable ORDS on LOGIN_APPROVAL_REQUESTS table ─────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled       => TRUE,
    p_schema        => 'ADMIN',
    p_object        => 'LOGIN_APPROVAL_REQUESTS',
    p_object_type   => 'TABLE',
    p_object_alias  => 'login_approval_requests',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/


-- ── 18. Sample products — Java Rocks (coffee store) ───────────────────────────

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

-- ── 19. Sample customers ───────────────────────────────────────────────────────

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
SELECT 'login_approval_requests', COUNT(*) FROM login_approval_requests;

exit
