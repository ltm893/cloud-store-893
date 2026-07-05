-- verify-test-sales-matrix.sql
-- Confirm npm run seed:test-sales-matrix created the expected 40 sales.
--
-- Identifies matrix sales by till register_id:
--   tablet-seed-credit-only   (20 sales, card only, credit_only till)
--   tablet-seed-cash-credit   (20 sales, card/cash/split, cash_and_credit till)
--
-- Run in Database Actions / SQLcl as ADMIN after seed:test-sales-matrix.
-- Or: npm run verify:test-sales-matrix
--     ./scripts/db/run-sql.sh scripts/db/verify-test-sales-matrix.sql
-- If you wiped all other sales, matrix_sales will equal the full sales table.

-- ── 1. Row listing (sanity check) ───────────────────────────────────────────

SELECT
  s.order_number,
  t.register_id,
  t.till_type,
  s.payment_method,
  s.total,
  s.register_total,
  s.cash_due,
  CASE WHEN s.linked_893 = 1 THEN c.name END AS linked_customer,
  s.created_at
FROM sales s
LEFT JOIN tills t ON t.id = s.till_id
LEFT JOIN customers c ON c.id = s.customer_id
WHERE t.register_id IN ('tablet-seed-credit-only', 'tablet-seed-cash-credit')
ORDER BY s.order_number;

-- ── 2. Expected vs actual counts (PASS / FAIL) ─────────────────────────────

WITH matrix_sales AS (
  SELECT s.*, t.register_id, t.till_type
  FROM sales s
  JOIN tills t ON t.id = s.till_id
  WHERE t.register_id IN ('tablet-seed-credit-only', 'tablet-seed-cash-credit')
),
payment_rows AS (
  SELECT sp.order_number, sp.payment_method, sp.amount, sp.change_given
  FROM sale_payments sp
  JOIN matrix_sales ms ON ms.order_number = sp.order_number
),
checks AS (
  SELECT 'total matrix sales' AS check_name,
         40 AS expected,
         COUNT(*) AS actual,
         CASE WHEN COUNT(*) = 40 THEN 'PASS' ELSE 'FAIL' END AS status
  FROM matrix_sales

  UNION ALL
  SELECT 'credit-only till sales',
         20,
         COUNT(*),
         CASE WHEN COUNT(*) = 20 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE register_id = 'tablet-seed-credit-only'

  UNION ALL
  SELECT 'cash+credit till sales',
         20,
         COUNT(*),
         CASE WHEN COUNT(*) = 20 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE register_id = 'tablet-seed-cash-credit'

  UNION ALL
  SELECT 'credit-only: all card payment_method',
         20,
         COUNT(*),
         CASE WHEN COUNT(*) = 20 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE register_id = 'tablet-seed-credit-only'
    AND payment_method = 'card'

  UNION ALL
  SELECT 'cash+credit: card sales',
         6,
         COUNT(*),
         CASE WHEN COUNT(*) = 6 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE register_id = 'tablet-seed-cash-credit'
    AND payment_method = 'card'

  UNION ALL
  SELECT 'cash+credit: cash sales',
         8,
         COUNT(*),
         CASE WHEN COUNT(*) = 8 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE register_id = 'tablet-seed-cash-credit'
    AND payment_method = 'cash'

  UNION ALL
  SELECT 'cash+credit: split sales',
         6,
         COUNT(*),
         CASE WHEN COUNT(*) = 6 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE register_id = 'tablet-seed-cash-credit'
    AND payment_method = 'split'

  UNION ALL
  SELECT 'linked customer sales (linked_893=1)',
         20,
         COUNT(*),
         CASE WHEN COUNT(*) = 20 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE linked_893 = 1

  UNION ALL
  SELECT 'walk-in sales (no customer_id)',
         20,
         COUNT(*),
         CASE WHEN COUNT(*) = 20 THEN 'PASS' ELSE 'FAIL' END
  FROM matrix_sales
  WHERE customer_id IS NULL

  UNION ALL
  SELECT 'split sales have 2 payment rows',
         6,
         COUNT(*),
         CASE WHEN COUNT(*) = 6 THEN 'PASS' ELSE 'FAIL' END
  FROM (
    SELECT ms.order_number
    FROM matrix_sales ms
    JOIN payment_rows pr ON pr.order_number = ms.order_number
    WHERE ms.payment_method = 'split'
    GROUP BY ms.order_number
    HAVING COUNT(*) = 2
  )

  UNION ALL
  SELECT 'exactly one cash sale with change_given',
         1,
         COUNT(*),
         CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
  FROM payment_rows
  WHERE payment_method = 'cash'
    AND NVL(change_given, 0) > 0

  UNION ALL
  SELECT 'sales with tax-exempt water lines',
         15,
         COUNT(DISTINCT si.order_number),
         CASE WHEN COUNT(DISTINCT si.order_number) = 15 THEN 'PASS' ELSE 'FAIL' END
  FROM sale_items si
  JOIN matrix_sales ms ON ms.order_number = si.order_number
  JOIN products p ON p.id = si.product_id
  WHERE p.product_type = 'water'
    AND p.tax_exempt = 1

  UNION ALL
  SELECT 'sale_items rows for matrix sales',
         54,
         COUNT(*),
         CASE WHEN COUNT(*) = 54 THEN 'PASS' ELSE 'FAIL' END
  FROM sale_items si
  JOIN matrix_sales ms ON ms.order_number = si.order_number

  UNION ALL
  SELECT 'sale_items units for matrix sales',
         58,
         SUM(si.quantity),
         CASE WHEN SUM(si.quantity) = 58 THEN 'PASS' ELSE 'FAIL' END
  FROM sale_items si
  JOIN matrix_sales ms ON ms.order_number = si.order_number

  UNION ALL
  SELECT 'sale_payments rows for matrix sales',
         46,
         COUNT(*),
         CASE WHEN COUNT(*) = 46 THEN 'PASS' ELSE 'FAIL' END
  FROM payment_rows
)
SELECT check_name, expected, actual, status
FROM checks
ORDER BY check_name;

-- ── 3. Payment breakdown ────────────────────────────────────────────────────

WITH matrix_sales AS (
  SELECT s.order_number, s.payment_method, t.register_id
  FROM sales s
  JOIN tills t ON t.id = s.till_id
  WHERE t.register_id IN ('tablet-seed-credit-only', 'tablet-seed-cash-credit')
)
SELECT
  ms.register_id,
  ms.payment_method AS sale_payment_method,
  sp.payment_method AS tender,
  COUNT(*) AS payment_rows,
  ROUND(SUM(sp.amount), 2) AS amount_total,
  ROUND(SUM(NVL(sp.change_given, 0)), 2) AS change_total
FROM matrix_sales ms
JOIN sale_payments sp ON sp.order_number = ms.order_number
GROUP BY ms.register_id, ms.payment_method, sp.payment_method
ORDER BY ms.register_id, ms.payment_method, sp.payment_method;

-- ── 4. Optional: confirm no other sales exist ─────────────────────────────

SELECT
  CASE
    WHEN all_cnt = matrix_cnt THEN 'PASS — all sales are from the matrix script'
    ELSE 'WARN — other sales exist outside matrix registers'
  END AS only_matrix_sales,
  all_cnt,
  matrix_cnt
FROM (
  SELECT
    (SELECT COUNT(*) FROM sales) AS all_cnt,
    (SELECT COUNT(*)
     FROM sales s
     JOIN tills t ON t.id = s.till_id
     WHERE t.register_id IN ('tablet-seed-credit-only', 'tablet-seed-cash-credit')
    ) AS matrix_cnt
  FROM dual
);

-- ── 5. Inventory (post-matrix — requires preflight in seed-test-sales-matrix.js) ─
-- Synced with scripts/test/lib/matrix-inventory.js + test/matrix-inventory.test.js

WITH expected_retail AS (
  SELECT '872000000303' AS barcode, 'hoodie' AS label, 6 AS qty_on_hand FROM dual UNION ALL
  SELECT '872000000301', 'tee', 8 FROM dual UNION ALL
  SELECT '872000000401', 'water16', 36 FROM dual UNION ALL
  SELECT '872000000404', 'waterGallon', 45 FROM dual UNION ALL
  SELECT '872000000403', 'sparkling', 44 FROM dual UNION ALL
  SELECT '872000000103', 'beans', 25 FROM dual UNION ALL
  SELECT '872000000201', 'tumbler', 18 FROM dual UNION ALL
  SELECT '872000000203', 'coldCup', 19 FROM dual
),
actual_retail AS (
  SELECT p.barcode, pi.quantity_on_hand
  FROM product_inventory pi
  JOIN products p ON p.id = pi.product_id
  WHERE p.barcode IN (
    '872000000303', '872000000301', '872000000401', '872000000404',
    '872000000403', '872000000103', '872000000201', '872000000203'
  )
),
retail_checks AS (
  SELECT
    'retail on_hand: ' || e.label AS check_name,
    e.qty_on_hand AS expected,
    a.quantity_on_hand AS actual,
    CASE
      WHEN a.quantity_on_hand IS NULL THEN 'FAIL (no product_inventory row — run seed.sql inventory sections)'
      WHEN a.quantity_on_hand = e.qty_on_hand THEN 'PASS'
      ELSE 'FAIL'
    END AS status
  FROM expected_retail e
  LEFT JOIN actual_retail a ON a.barcode = e.barcode
),
bulk_check AS (
  SELECT
    'kitchen_beans bulk on_hand (oz)' AS check_name,
    7962.5 AS expected,
    quantity_on_hand AS actual,
    CASE WHEN ABS(quantity_on_hand - 7962.5) < 0.01 THEN 'PASS' ELSE 'FAIL' END AS status
  FROM bulk_inventory
  WHERE sku_key = 'kitchen_beans'
),
matrix_sale_moves AS (
  SELECT COUNT(*) AS cnt
  FROM inventory_movements im
  JOIN sales s ON s.order_number = im.order_number
  JOIN tills t ON t.id = s.till_id
  WHERE im.reason = 'sale'
    AND im.product_id IS NOT NULL
    AND t.register_id IN ('tablet-seed-credit-only', 'tablet-seed-cash-credit')
),
matrix_consume_moves AS (
  SELECT COUNT(*) AS cnt
  FROM inventory_movements im
  JOIN sales s ON s.order_number = im.order_number
  JOIN tills t ON t.id = s.till_id
  WHERE im.reason = 'consume'
    AND im.bulk_sku_key = 'kitchen_beans'
    AND t.register_id IN ('tablet-seed-credit-only', 'tablet-seed-cash-credit')
),
movement_checks AS (
  SELECT 'matrix retail sale movements' AS check_name,
         31 AS expected,
         (SELECT cnt FROM matrix_sale_moves) AS actual,
         CASE
           WHEN (SELECT cnt FROM matrix_sale_moves) = 0 THEN
             'FAIL (0 rows — products likely lack track_inventory=1; run seed.sql §24–25)'
           WHEN (SELECT cnt FROM matrix_sale_moves) = 31 THEN 'PASS'
           ELSE 'FAIL'
         END AS status
  FROM dual
  UNION ALL
  SELECT 'matrix bulk consume movements',
         23,
         (SELECT cnt FROM matrix_consume_moves),
         CASE WHEN (SELECT cnt FROM matrix_consume_moves) = 23 THEN 'PASS' ELSE 'FAIL' END
  FROM dual
)
SELECT check_name, expected, actual, status FROM retail_checks
UNION ALL
SELECT check_name, expected, actual, status FROM bulk_check
UNION ALL
SELECT check_name, expected, actual, status FROM movement_checks
ORDER BY check_name;
