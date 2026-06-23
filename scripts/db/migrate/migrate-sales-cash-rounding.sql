-- Add nickel cash rounding columns to sales (idempotent).
-- Run after deploy when ORDS already exists: sqlplus ... @scripts/migrate-sales-cash-rounding.sql

BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE sales ADD (register_total NUMBER(10, 2))';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1430 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE sales ADD (cash_due NUMBER(10, 2))';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1430 THEN RAISE; END IF;
END;
/

UPDATE sales
SET register_total = total
WHERE register_total IS NULL;

COMMIT;
