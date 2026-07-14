-- PostgreSQL schema for cloud-store-893 (Aurora / local Compose)
-- Port of scripts/db/seed.sql without ORDS.ENABLE_* blocks.
-- Idempotent: drops and recreates objects.

BEGIN;

DROP VIEW IF EXISTS inventory_status_view CASCADE;
DROP VIEW IF EXISTS cart_view CASCADE;
DROP TABLE IF EXISTS inventory_movements CASCADE;
DROP TABLE IF EXISTS inventory_consumption_rules CASCADE;
DROP TABLE IF EXISTS product_inventory CASCADE;
DROP TABLE IF EXISTS bulk_inventory CASCADE;
DROP TABLE IF EXISTS sale_payments CASCADE;
DROP TABLE IF EXISTS sale_items CASCADE;
DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS till_close_approvals CASCADE;
DROP TABLE IF EXISTS tills CASCADE;
DROP TABLE IF EXISTS pos_sessions CASCADE;
DROP TABLE IF EXISTS till_open_approvals CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

CREATE TABLE products (
  id               INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barcode          VARCHAR(32)   NOT NULL UNIQUE,
  name             VARCHAR(200)  NOT NULL,
  product_type     VARCHAR(50)   NOT NULL,
  manufacturer     VARCHAR(200)  NOT NULL,
  price            NUMERIC(10, 2) NOT NULL,
  sale_price       NUMERIC(10, 2),
  track_inventory  SMALLINT      DEFAULT 0 NOT NULL,
  tax_exempt       SMALLINT      DEFAULT 0 NOT NULL
);

CREATE TABLE product_inventory (
  product_id       INTEGER PRIMARY KEY REFERENCES products(id),
  quantity_on_hand NUMERIC DEFAULT 0 NOT NULL,
  reorder_point    NUMERIC DEFAULT 0 NOT NULL,
  updated_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  CONSTRAINT product_inventory_qty_nonneg CHECK (quantity_on_hand >= 0)
);

CREATE TABLE bulk_inventory (
  sku_key           VARCHAR(50) PRIMARY KEY,
  name              VARCHAR(200) NOT NULL,
  quantity_on_hand  NUMERIC(12, 3) DEFAULT 0 NOT NULL,
  unit              VARCHAR(20)  DEFAULT 'oz' NOT NULL,
  reorder_point     NUMERIC(12, 3) DEFAULT 0 NOT NULL,
  updated_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  CONSTRAINT bulk_inventory_qty_nonneg CHECK (quantity_on_hand >= 0)
);

CREATE TABLE inventory_consumption_rules (
  product_type      VARCHAR(50) PRIMARY KEY,
  bulk_sku_key      VARCHAR(50) NOT NULL REFERENCES bulk_inventory(sku_key),
  quantity_per_unit NUMERIC(12, 3) NOT NULL,
  unit              VARCHAR(20)  NOT NULL
);

CREATE TABLE inventory_movements (
  id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id      INTEGER REFERENCES products(id),
  bulk_sku_key    VARCHAR(50) REFERENCES bulk_inventory(sku_key),
  delta           NUMERIC NOT NULL,
  quantity_after  NUMERIC NOT NULL,
  reason          VARCHAR(50) NOT NULL,
  order_number    VARCHAR(7),
  note            VARCHAR(500),
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  CONSTRAINT inventory_movements_target_ck CHECK (
    (product_id IS NOT NULL AND bulk_sku_key IS NULL)
    OR (product_id IS NULL AND bulk_sku_key IS NOT NULL)
  )
);

CREATE TABLE customers (
  id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name          VARCHAR(200)  NOT NULL,
  email         VARCHAR(200),
  phone         VARCHAR(50),
  address_line1 VARCHAR(200),
  address_line2 VARCHAR(200),
  city          VARCHAR(100),
  state         VARCHAR(50),
  postal_code   VARCHAR(20),
  card_fake     VARCHAR(64),
  member_code   VARCHAR(32)
);

CREATE TABLE cart_items (
  id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id INTEGER        NOT NULL REFERENCES products(id),
  quantity   INTEGER        DEFAULT 1 NOT NULL
);

CREATE TABLE sales (
  id                       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number             VARCHAR(7)    NOT NULL UNIQUE,
  total                    NUMERIC(10, 2)  NOT NULL,
  register_total           NUMERIC(10, 2),
  cash_due                 NUMERIC(10, 2),
  payment_method           VARCHAR(50)   NOT NULL,
  customer_id              INTEGER         REFERENCES customers(id),
  subtotal_pre_member      NUMERIC(10, 2)  NOT NULL,
  member_discount_pre_tax  NUMERIC(10, 2)  DEFAULT 0 NOT NULL,
  linked_893               SMALLINT      DEFAULT 0 NOT NULL,
  till_id                  INTEGER,
  created_at               TIMESTAMPTZ      DEFAULT NOW() NOT NULL
);

CREATE TABLE sale_items (
  id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number VARCHAR(7)   NOT NULL,
  product_id   INTEGER         NOT NULL REFERENCES products(id),
  quantity     INTEGER         NOT NULL,
  unit_price   NUMERIC(10, 2)  NOT NULL,
  line_total   NUMERIC(10, 2)  NOT NULL
);

CREATE TABLE sale_payments (
  id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number    VARCHAR(7)    NOT NULL REFERENCES sales(order_number),
  sequence_number INTEGER         NOT NULL,
  payment_method  VARCHAR(50)   NOT NULL,
  amount          NUMERIC(10, 2)  NOT NULL,
  tendered_amount NUMERIC(10, 2),
  change_given    NUMERIC(10, 2),
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE TABLE pos_sessions (
  id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  register_id   VARCHAR(64),
  cashier_sub   VARCHAR(256)  NOT NULL,
  cashier_email VARCHAR(256),
  status        VARCHAR(20)   NOT NULL,
  started_at    TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  ended_at      TIMESTAMPTZ
);

CREATE INDEX pos_sessions_register_idx
  ON pos_sessions (register_id, status, started_at);

CREATE INDEX pos_sessions_cashier_idx
  ON pos_sessions (cashier_sub, status, started_at);

CREATE TABLE till_open_approvals (
  id                     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_token          VARCHAR(64)   NOT NULL UNIQUE,
  status                 VARCHAR(20)   NOT NULL,
  pos_session_id         INTEGER         REFERENCES pos_sessions(id),
  cashier_sub            VARCHAR(256)  NOT NULL,
  cashier_email          VARCHAR(256),
  cashier_name           VARCHAR(200),
  register_id            VARCHAR(64),
  client_kind            VARCHAR(20),
  requested_at           TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  expires_at             TIMESTAMPTZ NOT NULL,
  resolved_at            TIMESTAMPTZ,
  resolved_by_sub        VARCHAR(256),
  resolved_by_email      VARCHAR(256),
  deny_reason            VARCHAR(500),
  till_type              VARCHAR(20),
  expected_opening_float NUMERIC(10, 2),
  opening_counted_float  NUMERIC(10, 2),
  opening_variance       NUMERIC(10, 2),
  opening_denominations  TEXT,
  till_submitted_at      TIMESTAMPTZ
);

CREATE INDEX till_open_approvals_status_idx
  ON till_open_approvals (status, expires_at);

CREATE TABLE tills (
  id                     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pos_session_id         INTEGER         NOT NULL REFERENCES pos_sessions(id),
  register_id            VARCHAR(64),
  cashier_sub            VARCHAR(256)  NOT NULL,
  cashier_email          VARCHAR(256),
  till_type              VARCHAR(20)   NOT NULL,
  expected_opening_float NUMERIC(10, 2),
  opening_counted_float  NUMERIC(10, 2),
  opening_denominations  TEXT,
  opening_variance       NUMERIC(10, 2),
  open_approval_token    VARCHAR(64),
  cash_sales             NUMERIC(10, 2)  DEFAULT 0 NOT NULL,
  credit_sales           NUMERIC(10, 2)  DEFAULT 0 NOT NULL,
  opened_at              TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  closed_at              TIMESTAMPTZ,
  status                 VARCHAR(20)   NOT NULL
);

CREATE INDEX tills_cashier_idx
  ON tills (cashier_sub, status, opened_at);

CREATE INDEX tills_register_idx
  ON tills (register_id, status, opened_at);

CREATE TABLE till_close_approvals (
  id                     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  close_token            VARCHAR(64)   NOT NULL UNIQUE,
  till_id                INTEGER         NOT NULL REFERENCES tills(id),
  register_id            VARCHAR(64),
  cashier_sub            VARCHAR(256)  NOT NULL,
  cashier_email          VARCHAR(256),
  cashier_name           VARCHAR(200),
  till_type              VARCHAR(20)   NOT NULL,
  expected_close_float   NUMERIC(10, 2),
  counted_close_float    NUMERIC(10, 2),
  close_variance         NUMERIC(10, 2),
  close_denominations    TEXT,
  cash_sales_total       NUMERIC(10, 2),
  change_given_total     NUMERIC(10, 2),
  opening_counted_float  NUMERIC(10, 2),
  status                 VARCHAR(20)   NOT NULL,
  requested_at           TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  expires_at             TIMESTAMPTZ NOT NULL,
  resolved_at            TIMESTAMPTZ,
  resolved_by_sub        VARCHAR(256),
  resolved_by_email      VARCHAR(256),
  deny_reason            VARCHAR(500)
);

CREATE INDEX till_close_approvals_status_idx
  ON till_close_approvals (status, expires_at);

CREATE VIEW cart_view AS
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

CREATE VIEW inventory_status_view AS
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

COMMIT;
