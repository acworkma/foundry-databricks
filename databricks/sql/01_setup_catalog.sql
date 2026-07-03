-- ===========================================================================
-- 01_setup_catalog.sql
-- Create the Unity Catalog catalog and schema for the Data Quality Agent demo.
--
-- Run this in a Databricks SQL editor / notebook attached to a SQL warehouse,
-- or via the bundled run_sql.py helper (which substitutes ${CATALOG} /
-- ${SCHEMA}). Placeholders (defaults): ${CATALOG} = datahub_demo,
-- ${SCHEMA} = quality.
--
-- How you create the catalog depends on how your Unity Catalog metastore
-- stores managed data. Pick one:
--   * Metastore with a configured storage root — uncomment Option 1.
--   * Account-level Default Storage — create the catalog once in Catalog
--     Explorer (Create catalog > Default storage), or uncomment Option 2 and
--     supply your own managed location.
-- The CREATE SCHEMA statement is all the data and function scripts require, so
-- run it once the catalog exists.
-- ===========================================================================

-- Option 1 — metastore with a configured storage root:
-- CREATE CATALOG IF NOT EXISTS ${CATALOG}
--   COMMENT 'Demo catalog for the Foundry + Databricks Data Quality Agent.';

-- Option 2 — supply an explicit managed location:
-- CREATE CATALOG IF NOT EXISTS ${CATALOG}
--   MANAGED LOCATION 'abfss://<container>@<account>.dfs.core.windows.net/<path>'
--   COMMENT 'Demo catalog for the Foundry + Databricks Data Quality Agent.';

CREATE SCHEMA IF NOT EXISTS ${CATALOG}.${SCHEMA}
  COMMENT 'Sample DataHub tables (synthetic, non-PII) plus data quality functions.';
