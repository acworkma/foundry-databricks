-- ===========================================================================
-- 03_quality_functions.sql
-- Unity Catalog functions that implement the six-dimension data quality model.
--
-- Two layers:
--   1. Reusable SCALAR functions (scoring, severity, freshness) -- these are
--      the deterministic "skill" logic and make ideal agent tools.
--   2. Per-table TABLE functions (assess_*) that run the real checks against
--      the sample tables and return a tidy scorecard.
--
-- Why per-table functions? SQL UDFs cannot run dynamic SQL, so a single
-- "assess any table" function is not possible in pure SQL. For arbitrary
-- tables, use the Genie Space or the custom MCP server,
-- both of which can generate SQL dynamically.
--
-- All object names are fully qualified with ${CATALOG}.${SCHEMA} so the script
-- runs statement-by-statement (e.g. via run_sql.py) without relying on USE.
-- Placeholders (defaults): ${CATALOG} = datahub_demo, ${SCHEMA} = quality.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Scalar scoring helpers (reusable across any assessment)
-- ---------------------------------------------------------------------------

-- Score = 1 - (issues / checks), clamped to [0,1]. Empty checks => perfect.
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.dq_ratio_score(issues BIGINT, checks BIGINT)
RETURNS DOUBLE
COMMENT 'Fraction of checks that passed, in [0,1]. issues/checks bad ratio subtracted from 1.'
RETURN CASE WHEN checks IS NULL OR checks <= 0 THEN 1.0
            ELSE greatest(0.0, 1.0 - (issues * 1.0 / checks)) END;

-- Freshness score: full marks within target_days, decays linearly over a year.
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.dq_freshness_score(age_days INT, target_days INT)
RETURNS DOUBLE
COMMENT 'Timeliness score from data age in days versus an expected refresh target.'
RETURN CASE WHEN age_days IS NULL THEN NULL
            WHEN age_days <= target_days THEN 1.0
            ELSE greatest(0.0, 1.0 - ((age_days - target_days) / 365.0)) END;

-- Composite score = mean of the provided dimension scores (nulls ignored).
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.dq_composite(
  accuracy DOUBLE, completeness DOUBLE, consistency DOUBLE,
  timeliness DOUBLE, validity DOUBLE, uniqueness DOUBLE)
RETURNS DOUBLE
COMMENT 'Overall composite score: average of the six dimension scores, ignoring NULLs.'
RETURN (
  coalesce(accuracy,0) + coalesce(completeness,0) + coalesce(consistency,0) +
  coalesce(timeliness,0) + coalesce(validity,0) + coalesce(uniqueness,0)
) / (
  (CASE WHEN accuracy     IS NULL THEN 0 ELSE 1 END) +
  (CASE WHEN completeness IS NULL THEN 0 ELSE 1 END) +
  (CASE WHEN consistency  IS NULL THEN 0 ELSE 1 END) +
  (CASE WHEN timeliness   IS NULL THEN 0 ELSE 1 END) +
  (CASE WHEN validity     IS NULL THEN 0 ELSE 1 END) +
  (CASE WHEN uniqueness   IS NULL THEN 0 ELSE 1 END)
);

-- Severity classification per the pilot scoring model.
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.dq_severity(score DOUBLE)
RETURNS STRING
COMMENT 'Maps a 0..1 score to Healthy / Needs Attention / High Risk / Critical.'
RETURN CASE WHEN score IS NULL   THEN 'Not Assessed'
            WHEN score >= 0.95    THEN 'Healthy'
            WHEN score >= 0.85    THEN 'Needs Attention'
            WHEN score >= 0.70    THEN 'High Risk'
            ELSE                       'Critical' END;

-- Suggested action per the pilot scoring model.
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.dq_recommend(score DOUBLE)
RETURNS STRING
COMMENT 'Suggested action for a given score, aligned to the severity bands.'
RETURN CASE WHEN score IS NULL THEN 'Define a rule so this dimension can be assessed.'
            WHEN score >= 0.95  THEN 'Publish as low-risk; monitor trend.'
            WHEN score >= 0.85  THEN 'Review findings; assign remediation if business impact exists.'
            WHEN score >= 0.70  THEN 'Create a work item; validate the upstream pipeline/source.'
            ELSE                     'Escalate; consider suppressing downstream use until resolved.' END;

-- ---------------------------------------------------------------------------
-- assess_customers()  -- exercises completeness, uniqueness, validity,
-- timeliness, consistency, and accuracy against the customers table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.assess_customers()
RETURNS TABLE (
  table_name STRING, dimension STRING, records_checked BIGINT,
  issues_found BIGINT, score DOUBLE, severity STRING, finding STRING)
COMMENT 'Six-dimension data quality assessment of the sample customers table.'
RETURN
  WITH m AS (
    SELECT
      count(*) AS n,
      sum(CASE WHEN email IS NULL THEN 1 ELSE 0 END)  AS null_email,
      sum(CASE WHEN region IS NULL THEN 1 ELSE 0 END) AS null_region,
      count(*) - count(DISTINCT customer_id)          AS dup_ids,
      sum(CASE WHEN email IS NOT NULL AND email NOT LIKE '%@%.%' THEN 1 ELSE 0 END) AS bad_email,
      sum(CASE WHEN region IS NOT NULL AND region NOT IN ('US-EAST','US-WEST','US-CENTRAL') THEN 1 ELSE 0 END) AS bad_region,
      sum(CASE WHEN signup_date > current_date() THEN 1 ELSE 0 END) AS future_signup,
      sum(CASE WHEN signup_date > to_date(last_updated_at) THEN 1 ELSE 0 END) AS signup_after_update,
      sum(CASE WHEN full_name IS NULL OR trim(full_name) = '' THEN 1 ELSE 0 END) AS missing_name,
      datediff(current_date(), to_date(max(last_updated_at))) AS age_days
    FROM ${CATALOG}.${SCHEMA}.customers
  )
  SELECT 'customers','completeness', n, null_email + null_region,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(null_email + null_region, 2*n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(null_email + null_region, 2*n)),
         concat(cast(null_email AS STRING), ' null email(s), ', cast(null_region AS STRING), ' null region(s).')
  FROM m
  UNION ALL
  SELECT 'customers','uniqueness', n, dup_ids,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(dup_ids, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(dup_ids, n)),
         concat(cast(dup_ids AS STRING), ' duplicate customer_id value(s).')
  FROM m
  UNION ALL
  SELECT 'customers','validity', 3*n, bad_email + bad_region + future_signup,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(bad_email + bad_region + future_signup, 3*n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(bad_email + bad_region + future_signup, 3*n)),
         concat(cast(bad_email AS STRING), ' malformed email(s), ', cast(bad_region AS STRING),
                ' invalid region(s), ', cast(future_signup AS STRING), ' future signup date(s).')
  FROM m
  UNION ALL
  SELECT 'customers','timeliness', n, CASE WHEN age_days > 30 THEN n ELSE 0 END,
         ${CATALOG}.${SCHEMA}.dq_freshness_score(age_days, 30),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_freshness_score(age_days, 30)),
         concat('Newest record is ', cast(age_days AS STRING), ' day(s) old (target 30).')
  FROM m
  UNION ALL
  SELECT 'customers','consistency', n, signup_after_update,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(signup_after_update, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(signup_after_update, n)),
         concat(cast(signup_after_update AS STRING), ' record(s) where signup_date is after last_updated_at.')
  FROM m
  UNION ALL
  SELECT 'customers','accuracy', n, missing_name,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(missing_name, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(missing_name, n)),
         concat(cast(missing_name AS STRING), ' record(s) missing a required full_name.')
  FROM m;

-- ---------------------------------------------------------------------------
-- assess_orders()  -- consistency (referential + reconciliation) and accuracy
-- (business-rule) heavy.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.assess_orders()
RETURNS TABLE (
  table_name STRING, dimension STRING, records_checked BIGINT,
  issues_found BIGINT, score DOUBLE, severity STRING, finding STRING)
COMMENT 'Six-dimension data quality assessment of the sample orders table.'
RETURN
  WITH o AS (
    SELECT
      count(*) AS n,
      sum(CASE WHEN customer_id IS NULL OR order_date IS NULL THEN 1 ELSE 0 END) AS null_keys,
      count(*) - count(DISTINCT order_id) AS dup_ids,
      sum(CASE WHEN status NOT IN ('PENDING','SHIPPED','DELIVERED','CANCELLED') THEN 1 ELSE 0 END) AS bad_status,
      sum(CASE WHEN ship_date < order_date THEN 1 ELSE 0 END) AS ship_before_order,
      datediff(current_date(), max(order_date)) AS age_days
    FROM ${CATALOG}.${SCHEMA}.orders
  ),
  ref AS (
    SELECT sum(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END) AS orphan_customers
    FROM ${CATALOG}.${SCHEMA}.orders ord
    LEFT JOIN ${CATALOG}.${SCHEMA}.customers c ON ord.customer_id = c.customer_id
  ),
  rec AS (
    SELECT count(*) AS total_mismatch
    FROM (
      SELECT ord.order_id, ord.order_total,
             coalesce(sum(oi.quantity * oi.unit_price), 0) AS items_total
      FROM ${CATALOG}.${SCHEMA}.orders ord
      LEFT JOIN ${CATALOG}.${SCHEMA}.order_items oi ON ord.order_id = oi.order_id
      GROUP BY ord.order_id, ord.order_total
      HAVING abs(ord.order_total - coalesce(sum(oi.quantity * oi.unit_price), 0)) > 0.01
    )
  )
  SELECT 'orders','completeness', o.n, o.null_keys,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(o.null_keys, o.n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(o.null_keys, o.n)),
         concat(cast(o.null_keys AS STRING), ' record(s) missing customer_id or order_date.')
  FROM o
  UNION ALL
  SELECT 'orders','uniqueness', o.n, o.dup_ids,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(o.dup_ids, o.n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(o.dup_ids, o.n)),
         concat(cast(o.dup_ids AS STRING), ' duplicate order_id value(s).')
  FROM o
  UNION ALL
  SELECT 'orders','validity', o.n, o.bad_status,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(o.bad_status, o.n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(o.bad_status, o.n)),
         concat(cast(o.bad_status AS STRING), ' order(s) with an invalid status value.')
  FROM o
  UNION ALL
  SELECT 'orders','timeliness', o.n, CASE WHEN o.age_days > 30 THEN o.n ELSE 0 END,
         ${CATALOG}.${SCHEMA}.dq_freshness_score(o.age_days, 30),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_freshness_score(o.age_days, 30)),
         concat('Newest order is ', cast(o.age_days AS STRING), ' day(s) old (target 30).')
  FROM o
  UNION ALL
  SELECT 'orders','consistency', o.n, ref.orphan_customers + rec.total_mismatch,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(ref.orphan_customers + rec.total_mismatch, o.n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(ref.orphan_customers + rec.total_mismatch, o.n)),
         concat(cast(ref.orphan_customers AS STRING), ' order(s) reference a missing customer; ',
                cast(rec.total_mismatch AS STRING), ' order(s) where order_total != sum(line items).')
  FROM o, ref, rec
  UNION ALL
  SELECT 'orders','accuracy', o.n, o.ship_before_order,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(o.ship_before_order, o.n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(o.ship_before_order, o.n)),
         concat(cast(o.ship_before_order AS STRING), ' order(s) where ship_date precedes order_date.')
  FROM o;

-- ---------------------------------------------------------------------------
-- assess_products()  -- the healthy baseline; should score near-perfect.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ${CATALOG}.${SCHEMA}.assess_products()
RETURNS TABLE (
  table_name STRING, dimension STRING, records_checked BIGINT,
  issues_found BIGINT, score DOUBLE, severity STRING, finding STRING)
COMMENT 'Six-dimension data quality assessment of the sample products table (healthy baseline).'
RETURN
  WITH p AS (
    SELECT
      count(*) AS n,
      sum(CASE WHEN product_name IS NULL OR category IS NULL OR unit_price IS NULL THEN 1 ELSE 0 END) AS null_cells,
      count(*) - count(DISTINCT product_id) AS dup_ids,
      sum(CASE WHEN unit_price <= 0 OR category NOT IN ('Widgets','Gadgets','Components','Kits') THEN 1 ELSE 0 END) AS invalid_vals,
      sum(CASE WHEN trim(product_name) = '' THEN 1 ELSE 0 END) AS blank_name,
      datediff(current_date(), to_date(max(updated_at))) AS age_days
    FROM ${CATALOG}.${SCHEMA}.products
  )
  SELECT 'products','completeness', n, null_cells,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(null_cells, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(null_cells, n)),
         concat(cast(null_cells AS STRING), ' record(s) with a null required field.')
  FROM p
  UNION ALL
  SELECT 'products','uniqueness', n, dup_ids,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(dup_ids, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(dup_ids, n)),
         concat(cast(dup_ids AS STRING), ' duplicate product_id value(s).')
  FROM p
  UNION ALL
  SELECT 'products','validity', n, invalid_vals,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(invalid_vals, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(invalid_vals, n)),
         concat(cast(invalid_vals AS STRING), ' record(s) with non-positive price or invalid category.')
  FROM p
  UNION ALL
  SELECT 'products','timeliness', n, CASE WHEN age_days > 30 THEN n ELSE 0 END,
         ${CATALOG}.${SCHEMA}.dq_freshness_score(age_days, 30),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_freshness_score(age_days, 30)),
         concat('Newest record is ', cast(age_days AS STRING), ' day(s) old (target 30).')
  FROM p
  UNION ALL
  SELECT 'products','consistency', n, CAST(NULL AS BIGINT),
         CAST(NULL AS DOUBLE), ${CATALOG}.${SCHEMA}.dq_severity(CAST(NULL AS DOUBLE)),
         'No cross-table consistency rule defined for products; not assessed.'
  FROM p
  UNION ALL
  SELECT 'products','accuracy', n, blank_name,
         ${CATALOG}.${SCHEMA}.dq_ratio_score(blank_name, n),
         ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_ratio_score(blank_name, n)),
         concat(cast(blank_name AS STRING), ' record(s) with a blank product_name.')
  FROM p;
