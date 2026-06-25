-- seed-bulk-inventory-migrate.sql — add kitchen bulk + drink consumption on existing ADB
--
-- Run in Database Actions as ADMIN (Run Script). Safe to re-run.
-- Also enables ORDS on new objects. Does NOT drop existing inventory_movements rows.

-- ── 1. Tables ───────────────────────────────────────────────────────────────

DECLARE
  tbl_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO tbl_count FROM user_tables WHERE table_name = 'BULK_INVENTORY';
  IF tbl_count = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE bulk_inventory (
        sku_key           VARCHAR2(50) PRIMARY KEY,
        name              VARCHAR2(200) NOT NULL,
        quantity_on_hand  NUMBER(12, 3) DEFAULT 0 NOT NULL,
        unit              VARCHAR2(20)  DEFAULT ''oz'' NOT NULL,
        reorder_point     NUMBER(12, 3) DEFAULT 0 NOT NULL,
        updated_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT bulk_inventory_qty_nonneg CHECK (quantity_on_hand >= 0)
      )';
  END IF;

  SELECT COUNT(*) INTO tbl_count FROM user_tables WHERE table_name = 'INVENTORY_CONSUMPTION_RULES';
  IF tbl_count = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE inventory_consumption_rules (
        product_type      VARCHAR2(50) PRIMARY KEY,
        bulk_sku_key      VARCHAR2(50) NOT NULL REFERENCES bulk_inventory(sku_key),
        quantity_per_unit NUMBER(12, 3) NOT NULL,
        unit              VARCHAR2(20)  NOT NULL
      )';
  END IF;
END;
/

-- Allow bulk rows in movement ledger
DECLARE
  col_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO col_count
  FROM user_tab_columns
  WHERE table_name = 'INVENTORY_MOVEMENTS' AND column_name = 'BULK_SKU_KEY';
  IF col_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE inventory_movements ADD (bulk_sku_key VARCHAR2(50))';
  END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE inventory_movements MODIFY product_id NULL';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

DECLARE
  fk_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO fk_count FROM user_constraints
  WHERE constraint_name = 'INVENTORY_MOVEMENTS_BULK_FK';
  IF fk_count = 0 THEN
    BEGIN
      EXECUTE IMMEDIATE '
        ALTER TABLE inventory_movements
        ADD CONSTRAINT inventory_movements_bulk_fk
        FOREIGN KEY (bulk_sku_key) REFERENCES bulk_inventory(sku_key)';
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END IF;
END;
/


-- ── 2. Seed kitchen beans + made coffee rule ──────────────────────────────────

MERGE INTO bulk_inventory bi
USING (
  SELECT 'kitchen_beans' AS sku_key,
         'Kitchen bulk coffee beans' AS name,
         8000 AS quantity_on_hand,
         'oz' AS unit,
         500 AS reorder_point
  FROM dual
) src
ON (bi.sku_key = src.sku_key)
WHEN NOT MATCHED THEN
  INSERT (sku_key, name, quantity_on_hand, unit, reorder_point, updated_at)
  VALUES (src.sku_key, src.name, src.quantity_on_hand, src.unit, src.reorder_point, SYSTIMESTAMP);

MERGE INTO inventory_consumption_rules r
USING (
  SELECT 'made coffee' AS product_type,
         'kitchen_beans' AS bulk_sku_key,
         1.5 AS quantity_per_unit,
         'oz' AS unit
  FROM dual
) src
ON (r.product_type = src.product_type)
WHEN MATCHED THEN
  UPDATE SET
    r.bulk_sku_key = src.bulk_sku_key,
    r.quantity_per_unit = src.quantity_per_unit,
    r.unit = src.unit
WHEN NOT MATCHED THEN
  INSERT (product_type, bulk_sku_key, quantity_per_unit, unit)
  VALUES (src.product_type, src.bulk_sku_key, src.quantity_per_unit, src.unit);


-- ── 3. ORDS ───────────────────────────────────────────────────────────────────

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled        => TRUE,
    p_schema         => 'ADMIN',
    p_object         => 'BULK_INVENTORY',
    p_object_type    => 'TABLE',
    p_object_alias   => 'bulk_inventory',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled        => TRUE,
    p_schema         => 'ADMIN',
    p_object         => 'INVENTORY_CONSUMPTION_RULES',
    p_object_type    => 'TABLE',
    p_object_alias   => 'inventory_consumption_rules',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

COMMIT;

SELECT 'bulk_inventory' AS section, COUNT(*) AS row_count FROM bulk_inventory
UNION ALL
SELECT 'inventory_consumption_rules', COUNT(*) FROM inventory_consumption_rules;
