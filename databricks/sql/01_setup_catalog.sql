-- ===========================================================================
-- 01_setup_catalog.sql
-- Create the Unity Catalog catalog and schema for the Data Quality Agent demo.
--
-- Run this in a Databricks SQL editor / notebook attached to a SQL warehouse
-- (or serverless SQL) in a Unity Catalog-enabled workspace, OR via the bundled
-- run_sql.py helper which substitutes ${CATALOG} / ${SCHEMA}.
--
-- Placeholders (defaults): ${CATALOG} = datahub_demo, ${SCHEMA} = quality.
--
-- NOTE: If your metastore uses account-level "Default Storage" (no metastore
-- storage root), CREATE CATALOG must be done once in the UI (Catalog Explorer
-- > Create catalog > Default storage), or supply a MANAGED LOCATION here. In
-- that case point ${CATALOG} at an existing catalog and just run the schema
-- statement below.
-- ===========================================================================

CREATE CATALOG IF NOT EXISTS ${CATALOG}
  COMMENT 'Demo catalog for the Foundry + Databricks Data Quality Agent.';

CREATE SCHEMA IF NOT EXISTS ${CATALOG}.${SCHEMA}
  COMMENT 'Sample DataHub tables (synthetic, non-PII) plus data quality functions.';
