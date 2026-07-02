# Databricks artifacts — sample data + data quality functions

This folder contains everything needed to stand up the **DataHub** demo dataset in
Unity Catalog and the **six-dimension data quality** logic that the Foundry agent calls.

All SQL is written with `${CATALOG}` / `${SCHEMA}` placeholders so you can target any
catalog/schema. Defaults are `datahub_demo` / `quality`.

## Contents

| File | Purpose |
|------|---------|
| `sql/01_setup_catalog.sql` | Create the catalog + schema. |
| `sql/02_sample_data.sql` | Seed synthetic, non-PII tables with **intentional defects** across all six quality dimensions. |
| `sql/03_quality_functions.sql` | Unity Catalog functions: scalar scoring helpers + per-table `assess_*` table functions. |
| `sql/04_run_assessment.sql` | Validation queries: full scorecard, composite score per table, and a "needs attention" list. |
| `run_sql.py` | Dependency-free helper to run the SQL against a SQL warehouse via the Statement Execution API. |
| `DATA_DICTIONARY.md` | Description of the sample tables and the defects seeded into each. |

## Prerequisites

- A **Unity Catalog-enabled** Azure Databricks workspace.
- A **SQL warehouse** (the built-in *Serverless Starter Warehouse* is fine).
- Permission to create a catalog/schema (`CREATE CATALOG` / `CREATE SCHEMA`) or an
  existing catalog you can create a schema in.

> **Default Storage note.** If your metastore uses account-level *Default Storage*
> (no metastore storage root), `CREATE CATALOG` via SQL is blocked. Create the catalog
> once in **Catalog Explorer → Create catalog → Default storage**, then point
> `${CATALOG}` at it and run only the schema + data + function scripts.

## Option A — run in the Databricks UI

1. Open **SQL Editor** (or a notebook) attached to a SQL warehouse.
2. Open each file in order (`01` → `04`), replace `${CATALOG}` / `${SCHEMA}` with your
   names (e.g. `datahub_demo` / `quality`), and run it.
3. `04_run_assessment.sql` should return findings for `customers` and `orders`, and a
   near-perfect score for `products`.

## Option B — run from your machine with `run_sql.py`

`run_sql.py` uses only the Python standard library. Authenticate with either a Databricks
personal access token or a Microsoft Entra token.

```bash
# Databricks workspace host and a SQL warehouse id
export DATABRICKS_HOST="https://<databricks-host>.azuredatabricks.net"
export DATABRICKS_WAREHOUSE_ID="<warehouse-id>"

# Auth: a Databricks PAT, OR an Entra token for the Databricks resource
export DATABRICKS_TOKEN="$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv | tr -d '\r\n')"

# Optional: target catalog/schema (defaults: datahub_demo / quality)
export DATABRICKS_CATALOG="datahub_demo"
export DATABRICKS_SCHEMA="quality"

python3 run_sql.py \
  sql/01_setup_catalog.sql \
  sql/02_sample_data.sql \
  sql/03_quality_functions.sql \
  sql/04_run_assessment.sql
```

Find a warehouse id under **SQL Warehouses → (your warehouse) → Connection details**,
or list them: `GET /api/2.0/sql/warehouses`.

## What "good" looks like

Running `04_run_assessment.sql` produces a scorecard like:

| table | composite | severity | why |
|-------|-----------|----------|-----|
| `products` | ~1.00 | **Healthy** | Clean baseline table. |
| `customers` | ~0.77 | **High Risk** | Null emails/regions, a duplicate key, malformed email, invalid region, future signup date, stale load. |
| `orders` | ~0.77 | **High Risk** | Orphaned customer reference, order-total mismatch, invalid status, ship-before-order, stale load. |

The contrast between a healthy table and two problem tables is intentional so a single
run demonstrates the full severity range.

## How this maps to the agent

- The `assess_*` functions and scalar scorers are exposed to Foundry as tools via the
  **Unity Catalog Functions managed MCP server** (Pattern B — see
  [`docs/integration/pattern-b-uc-functions-mcp.md`](../docs/integration/pattern-b-uc-functions-mcp.md)).
- Natural-language questions over the same tables are answered via a **Genie Space**
  (Pattern A — see [`docs/integration/pattern-a-genie-mcp.md`](../docs/integration/pattern-a-genie-mcp.md)).
