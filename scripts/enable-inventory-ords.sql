-- enable-inventory-ords.sql — expose inventory tables/views to ORDS (admin + app)
--
-- Run in Database Actions as ADMIN after seed-inventory-backfill.sql if you did
-- not run the full scripts/seed.sql ORDS blocks (sections 17–19).
-- Safe to re-run.

-- ── Ensure objects exist ────────────────────────────────────────────────────

DECLARE
  tbl_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO tbl_count FROM user_tables WHERE table_name = 'INVENTORY_MOVEMENTS';
  IF tbl_count = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE inventory_movements (
        id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        product_id      NUMBER NOT NULL REFERENCES products(id),
        delta           NUMBER NOT NULL,
        quantity_after  NUMBER NOT NULL,
        reason          VARCHAR2(50) NOT NULL,
        order_number    VARCHAR2(64),
        note            VARCHAR2(500),
        created_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
      )';
  END IF;
END;
/

BEGIN EXECUTE IMMEDIATE 'DROP VIEW inventory_status_view'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

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


-- ── Enable ORDS REST handlers ───────────────────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled        => TRUE,
    p_schema         => 'ADMIN',
    p_object         => 'PRODUCT_INVENTORY',
    p_object_type    => 'TABLE',
    p_object_alias   => 'product_inventory',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled        => TRUE,
    p_schema         => 'ADMIN',
    p_object         => 'INVENTORY_MOVEMENTS',
    p_object_type    => 'TABLE',
    p_object_alias   => 'inventory_movements',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled        => TRUE,
    p_schema         => 'ADMIN',
    p_object         => 'INVENTORY_STATUS_VIEW',
    p_object_type    => 'VIEW',
    p_object_alias   => 'inventory_status_view',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

COMMIT;
