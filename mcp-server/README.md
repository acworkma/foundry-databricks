# Custom "assess any table" MCP server (Pattern E)

A small, dependency-light MCP server that runs the same six-dimension data-quality
scoring model as the Unity Catalog Functions path, but against **any** Unity Catalog
table — not just the pre-defined sample tables. It is the "build-your-own" integration
pattern, hosted privately on **dedicated (classic Pro) compute**.

## What it does

| Tool | Purpose |
|------|---------|
| `list_tables(catalog, schema)` | List tables/views in a Unity Catalog schema. |
| `assess_table(catalog, schema, table)` | Score a table across completeness, uniqueness, validity, timeliness, consistency, and accuracy; return the JSON report contract (composite score, severity, recommendations). |

Known sample tables (`customers`, `orders`, `products`) use **exact rule packs** ported
from `databricks/sql/03_quality_functions.sql`, so scores match the UC Functions baseline.
Any other table is profiled **generically** (completeness across all columns, uniqueness on
a detected key, timeliness on a detected date column); dimensions with no generic rule are
reported as *Not Assessed*.

## Auth model — user passthrough (approach A)

The server holds **no** data-plane credential. Foundry's OAuth Identity Passthrough
connection forwards the signed-in user's Azure Databricks-scoped token
(`<databricks-first-party-app-id>/user_impersonation`) as `Authorization: Bearer` on every
MCP call. Each tool reads that header and forwards it to the Databricks SQL Statement
Execution API, so queries run **as the user** and Unity Catalog enforces that user's grants.

> Prerequisite: every calling user must be a Databricks principal with the relevant Unity
> Catalog grants (and usage on the dedicated warehouse).

## Configuration (environment)

| Variable | Description |
|----------|-------------|
| `DATABRICKS_HOST` | Workspace hostname or URL, e.g. `https://<workspace-host>`. |
| `DATABRICKS_WAREHOUSE_ID` | The dedicated (classic Pro) SQL warehouse id. |
| `PORT` | Listen port (default `8000`). |

## Run locally

```bash
pip install -r requirements.txt
export DATABRICKS_HOST="https://<workspace-host>"
export DATABRICKS_WAREHOUSE_ID="<warehouse-id>"
python server.py            # serves streamable-HTTP MCP at /mcp
```

## Test (no dependencies)

```bash
python3 test_scoring.py     # parity tests for the ported scoring model
```

## Build the image (no local Docker needed)

```bash
az acr build --registry <acr-name> --image dq-mcp-server:latest .
```

## Files

- `scoring.py` — ported six-dimension scoring math (pure stdlib, unit-tested).
- `databricks_client.py` — SQL Statement Execution API client; forwards the caller's token.
- `rulepacks.py` — exact rule packs for the sample tables + a generic profiler.
- `server.py` — the MCP server (streamable-HTTP, endpoint `/mcp`).
- `test_scoring.py` — local parity tests.
- `Dockerfile`, `requirements.txt` — container build.

See `docs/integration/custom-mcp-server.md` for the full private deployment guide.
