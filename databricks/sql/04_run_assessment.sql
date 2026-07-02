-- ===========================================================================
-- 04_run_assessment.sql
-- Run the data quality assessment and produce the scorecard + composite score.
-- Use these queries to validate the demo and as the shape of output the agent
-- summarizes into a report.
--
-- All names are fully qualified with ${CATALOG}.${SCHEMA} so each query runs
-- independently (e.g. via run_sql.py) without relying on USE.
-- Placeholders (defaults): ${CATALOG} = datahub_demo, ${SCHEMA} = quality.
-- ===========================================================================

-- 1) Full dimension-level scorecard across all sample tables.
SELECT * FROM ${CATALOG}.${SCHEMA}.assess_customers()
UNION ALL SELECT * FROM ${CATALOG}.${SCHEMA}.assess_orders()
UNION ALL SELECT * FROM ${CATALOG}.${SCHEMA}.assess_products()
ORDER BY table_name, dimension;

-- 2) Composite score + overall severity per table.
WITH scores AS (
  SELECT * FROM ${CATALOG}.${SCHEMA}.assess_customers()
  UNION ALL SELECT * FROM ${CATALOG}.${SCHEMA}.assess_orders()
  UNION ALL SELECT * FROM ${CATALOG}.${SCHEMA}.assess_products()
),
pivoted AS (
  SELECT
    table_name,
    max(CASE WHEN dimension = 'accuracy'     THEN score END) AS accuracy,
    max(CASE WHEN dimension = 'completeness' THEN score END) AS completeness,
    max(CASE WHEN dimension = 'consistency'  THEN score END) AS consistency,
    max(CASE WHEN dimension = 'timeliness'   THEN score END) AS timeliness,
    max(CASE WHEN dimension = 'validity'     THEN score END) AS validity,
    max(CASE WHEN dimension = 'uniqueness'   THEN score END) AS uniqueness
  FROM scores
  GROUP BY table_name
)
SELECT
  table_name,
  round(accuracy, 3)     AS accuracy,
  round(completeness, 3) AS completeness,
  round(consistency, 3)  AS consistency,
  round(timeliness, 3)   AS timeliness,
  round(validity, 3)     AS validity,
  round(uniqueness, 3)   AS uniqueness,
  round(${CATALOG}.${SCHEMA}.dq_composite(accuracy, completeness, consistency, timeliness, validity, uniqueness), 3) AS composite_score,
  ${CATALOG}.${SCHEMA}.dq_severity(${CATALOG}.${SCHEMA}.dq_composite(accuracy, completeness, consistency, timeliness, validity, uniqueness)) AS overall_severity,
  ${CATALOG}.${SCHEMA}.dq_recommend(${CATALOG}.${SCHEMA}.dq_composite(accuracy, completeness, consistency, timeliness, validity, uniqueness)) AS recommended_action
FROM pivoted
ORDER BY composite_score;

-- 3) Just the findings that need attention (score below the "Healthy" band).
SELECT table_name, dimension, issues_found, round(score, 3) AS score, severity, finding
FROM (
  SELECT * FROM ${CATALOG}.${SCHEMA}.assess_customers()
  UNION ALL SELECT * FROM ${CATALOG}.${SCHEMA}.assess_orders()
  UNION ALL SELECT * FROM ${CATALOG}.${SCHEMA}.assess_products()
)
WHERE score IS NULL OR score < 0.95
ORDER BY score NULLS LAST, table_name, dimension;
