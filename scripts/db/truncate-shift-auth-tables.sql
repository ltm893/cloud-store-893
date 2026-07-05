-- Truncate supervisor till approvals and till state (test cleanup).
-- Does NOT touch products, sales, cart, or inventory.
-- till_close_approvals is cleared first (FK to tills); tills references pos_sessions.

SET SERVEROUTPUT ON

PROMPT Before:
SELECT 'till_open_approvals' AS table_name, COUNT(*) AS row_count FROM till_open_approvals
UNION ALL
SELECT 'pos_sessions', COUNT(*) FROM pos_sessions
UNION ALL
SELECT 'tills', COUNT(*) FROM tills
UNION ALL
SELECT 'till_close_approvals', COUNT(*) FROM till_close_approvals;

BEGIN
  EXECUTE IMMEDIATE 'TRUNCATE TABLE till_close_approvals';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE tills';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE till_open_approvals';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE pos_sessions';
END;
/

COMMIT;

PROMPT After:
SELECT 'till_open_approvals' AS table_name, COUNT(*) AS row_count FROM till_open_approvals
UNION ALL
SELECT 'pos_sessions', COUNT(*) FROM pos_sessions
UNION ALL
SELECT 'tills', COUNT(*) FROM tills
UNION ALL
SELECT 'till_close_approvals', COUNT(*) FROM till_close_approvals;

PROMPT Done. Cashiers must sign in again; supervisors will approve new till opens.
