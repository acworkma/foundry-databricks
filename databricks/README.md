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
| `sql/05_grant_mcp_identity.sql` | Grant the Foundry MCP identity access to the functions (+ ownership-chaining fix). Needed for the [UC Functions MCP](../docs/integration/uc-functions-managed-mcp.md) tool. |
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

# Create the schema, load sample data, and register the quality functions:
python3 run_sql.py \
  sql/01_setup_catalog.sql \
  sql/02_sample_data.sql \
  sql/03_quality_functions.sql

# Run the assessment and print the scorecard inline:
python3 run_sql.py --show-results sql/04_run_assessment.sql
```

`--show-results` (or `-r`) prints each statement's returned rows as a table, so the
assessment scorecard and findings appear directly in your terminal.

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

## Authorize the Foundry MCP identity

The [Unity Catalog Functions MCP](../docs/integration/uc-functions-managed-mcp.md) tool calls
these functions as the Foundry **project's managed identity** (Microsoft Entra service
identity). That identity must exist in the workspace as a service principal and hold
privileges on the `${SCHEMA}` schema. After adding it (Databricks **Settings → Identity and
access → Service principals → Microsoft Entra managed**, using the project MI Application ID),
run `sql/05_grant_mcp_identity.sql` — it grants the identity `USE CATALOG` / `USE SCHEMA` /
`SELECT` / `EXECUTE`, and also fixes **ownership chaining** (a UC SQL function runs its body as
the function *owner*, so the owner needs an explicit privilege chain too; otherwise calls fail
with `INSUFFICIENT_PERMISSIONS … SQLSTATE 42501`). See
[managed-identity.md](../docs/services/managed-identity.md#foundry-project-managed-identity--databricks-uc-functions-mcp)
for the end-to-end identity flow.

## How this maps to the agent

- The `assess_*` functions and scalar scorers are exposed to Foundry as tools via the
  **Unity Catalog Functions managed MCP server** (see
  [`docs/integration/uc-functions-managed-mcp.md`](../docs/integration/uc-functions-managed-mcp.md)).
- Natural-language questions over the same tables are answered via a **Genie Space**
  (see [`docs/integration/genie-managed-mcp.md`](../docs/integration/genie-managed-mcp.md)).
