-- Add opening-till columns to login_approval_requests (non-destructive).
-- Safe to re-run. Then refresh ORDS REST metadata for the table.
-- Run: ./scripts/migrate-login-approval-till.sh

WHENEVER SQLERROR EXIT SQL.SQLCODE

DECLARE
  PROCEDURE add_column(p_ddl VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_ddl;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -1430 THEN
        RAISE;
      END IF;
  END;
BEGIN
  add_column('ALTER TABLE login_approval_requests ADD cash_mode VARCHAR2(20)');
  add_column('ALTER TABLE login_approval_requests ADD expected_opening_float NUMBER(10, 2)');
  add_column('ALTER TABLE login_approval_requests ADD opening_counted_float NUMBER(10, 2)');
  add_column('ALTER TABLE login_approval_requests ADD opening_variance NUMBER(10, 2)');
  add_column('ALTER TABLE login_approval_requests ADD opening_denominations CLOB');
  add_column('ALTER TABLE login_approval_requests ADD till_submitted_at TIMESTAMP');
END;
/

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

SELECT column_name
  FROM user_tab_columns
 WHERE table_name = 'LOGIN_APPROVAL_REQUESTS'
   AND column_name IN (
         'CASH_MODE',
         'EXPECTED_OPENING_FLOAT',
         'OPENING_COUNTED_FLOAT',
         'OPENING_VARIANCE',
         'OPENING_DENOMINATIONS',
         'TILL_SUBMITTED_AT'
       )
 ORDER BY column_name;

exit
