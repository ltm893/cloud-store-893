-- Migrate legacy register_shifts / login_approval_requests schema to pos_sessions + tills.
-- Run once on an existing OCI DB before deploying the new server image.
-- Fresh installs should use scripts/seed.sql instead.

SET SERVEROUTPUT ON

DECLARE
  has_old_shifts NUMBER := 0;
  has_old_approvals NUMBER := 0;
BEGIN
  SELECT COUNT(*) INTO has_old_shifts FROM user_tables WHERE table_name = 'REGISTER_SHIFTS';
  SELECT COUNT(*) INTO has_old_approvals FROM user_tables WHERE table_name = 'LOGIN_APPROVAL_REQUESTS';

  IF has_old_shifts = 0 AND has_old_approvals = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Legacy tables not found — skip migration or run seed.sql on empty DB.');
    RETURN;
  END IF;

  DBMS_OUTPUT.PUT_LINE('Migrating register_shifts → tills and login_approval_requests → till_open_approvals…');

  -- Create new tables if missing (subset of seed.sql; ORDS auto-exposes after grant).
  BEGIN EXECUTE IMMEDIATE '
    CREATE TABLE pos_sessions (
      id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      register_id   VARCHAR2(64),
      cashier_sub   VARCHAR2(256)  NOT NULL,
      cashier_email VARCHAR2(256),
      cashier_name  VARCHAR2(200),
      status        VARCHAR2(20)   NOT NULL,
      started_at    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
      ended_at      TIMESTAMP
    )'; EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN EXECUTE IMMEDIATE '
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
    )'; EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN EXECUTE IMMEDIATE '
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
    )'; EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN EXECUTE IMMEDIATE '
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
    )'; EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Backfill pos_sessions from distinct open shifts (one session per legacy shift).
  EXECUTE IMMEDIATE '
    INSERT INTO pos_sessions (register_id, cashier_sub, cashier_email, status, started_at, ended_at)
    SELECT register_id, cashier_sub, cashier_email,
           CASE WHEN status = ''closed'' THEN ''ended'' ELSE ''active'' END,
           opened_at,
           closed_at
    FROM register_shifts rs
    WHERE NOT EXISTS (
      SELECT 1 FROM pos_sessions ps
      WHERE ps.cashier_sub = rs.cashier_sub
        AND ps.started_at = rs.opened_at
    )';

  -- Map shifts to tills using matching pos_session by cashier + opened_at.
  EXECUTE IMMEDIATE '
    INSERT INTO tills (
      pos_session_id, register_id, cashier_sub, cashier_email, till_type,
      expected_opening_float, opening_counted_float, opening_variance,
      open_approval_token, opened_at, closed_at, status
    )
    SELECT ps.id, rs.register_id, rs.cashier_sub, rs.cashier_email,
           NVL(rs.cash_mode, ''credit_only''),
           rs.expected_opening_float, rs.opening_counted_float, rs.opening_variance,
           rs.approval_request_token, rs.opened_at, rs.closed_at,
           CASE WHEN rs.status = ''open'' THEN ''active'' WHEN rs.status = ''closed'' THEN ''closed'' ELSE rs.status END
    FROM register_shifts rs
    JOIN pos_sessions ps
      ON ps.cashier_sub = rs.cashier_sub AND ps.started_at = rs.opened_at
    WHERE NOT EXISTS (
      SELECT 1 FROM tills t WHERE t.open_approval_token = rs.approval_request_token
    )';

  EXECUTE IMMEDIATE '
    INSERT INTO till_open_approvals (
      request_token, status, cashier_sub, cashier_email, cashier_name, register_id,
      client_kind, requested_at, expires_at, resolved_at, resolved_by_sub, resolved_by_email,
      deny_reason, till_type, expected_opening_float, opening_counted_float, opening_variance,
      opening_denominations, till_submitted_at
    )
    SELECT request_token, status, cashier_sub, cashier_email, cashier_name, register_id,
           client_kind, requested_at, expires_at, resolved_at, resolved_by_sub, resolved_by_email,
           deny_reason, cash_mode, expected_opening_float, opening_counted_float, opening_variance,
           opening_denominations, till_submitted_at
    FROM login_approval_requests lar
    WHERE NOT EXISTS (
      SELECT 1 FROM till_open_approvals toa WHERE toa.request_token = lar.request_token
    )';

  EXECUTE IMMEDIATE '
    INSERT INTO till_close_approvals (
      close_token, till_id, register_id, cashier_sub, cashier_email, cashier_name,
      till_type, expected_close_float, counted_close_float, close_variance, close_denominations,
      cash_sales_total, change_given_total, opening_counted_float, status,
      requested_at, expires_at, resolved_at, resolved_by_sub, resolved_by_email, deny_reason
    )
    SELECT rsc.close_token, t.id, rsc.register_id, rsc.cashier_sub, rsc.cashier_email, rsc.cashier_name,
           NVL(rsc.cash_mode, ''credit_only''), rsc.expected_close_float, rsc.counted_close_float,
           rsc.close_variance, rsc.close_denominations, rsc.cash_sales_total, rsc.change_given_total,
           rsc.opening_counted_float, rsc.status, rsc.requested_at, rsc.expires_at,
           rsc.resolved_at, rsc.resolved_by_sub, rsc.resolved_by_email, rsc.deny_reason
    FROM register_shift_closes rsc
    JOIN tills t ON t.id = rsc.shift_id
    WHERE NOT EXISTS (
      SELECT 1 FROM till_close_approvals tca WHERE tca.close_token = rsc.close_token
    )';

  -- sales.shift_id → till_id when column exists
  BEGIN
    EXECUTE IMMEDIATE 'ALTER TABLE sales RENAME COLUMN shift_id TO till_id';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  DBMS_OUTPUT.PUT_LINE('Migration complete. Drop legacy tables after verifying ORDS + app.');
END;
/

COMMIT;
