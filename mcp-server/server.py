"""Custom "assess any table" MCP server (Pattern E, private / dedicated compute).

Exposes deterministic six-dimension data-quality scoring over *arbitrary* Unity
Catalog tables via the Databricks SQL Statement Execution API. Runs on dedicated
(classic Pro) compute and is reached privately by the Foundry agent.

Auth model (user passthrough, approach A): Foundry's OAuth Identity Passthrough
connection forwards the signed-in user's Azure Databricks-scoped token as
``Authorization: Bearer`` on every MCP call. Each tool reads that header and forwards
it to Databricks, so queries run *as the user* and Unity Catalog enforces their grants.
The server holds no static data-plane credential.

Transport: streamable-HTTP, endpoint ``/mcp`` (the shape Foundry's custom MCP tool expects).
"""
from __future__ import annotations

import datetime as _dt
import os
from typing import Any

from mcp.server.fastmcp import Context, FastMCP

import rulepacks
import scoring
from databricks_client import DatabricksError, DatabricksSqlClient

DATABRICKS_HOST = os.environ.get("DATABRICKS_HOST", "")
DATABRICKS_WAREHOUSE_ID = os.environ.get("DATABRICKS_WAREHOUSE_ID", "")

mcp = FastMCP(
    name="databricks-data-quality",
    instructions=(
        "Deterministic six-dimension data-quality assessment for any Unity Catalog "
        "table. Use assess_table to score a table; use list_tables to discover tables "
        "in a schema."
    ),
    stateless_http=True,
)


class _AuthError(RuntimeError):
    pass


def _bearer_token(ctx: Context) -> str:
    """Pull the forwarded user token from the incoming Authorization header."""
    request = getattr(ctx.request_context, "request", None)
    header = ""
    if request is not None:
        header = request.headers.get("authorization", "") or request.headers.get("Authorization", "")
    if not header.lower().startswith("bearer "):
        raise _AuthError(
            "Missing bearer token. This tool requires Foundry OAuth Identity Passthrough "
            "so the caller's Azure Databricks token is forwarded on each request."
        )
    return header.split(" ", 1)[1].strip()


def _client() -> DatabricksSqlClient:
    if not DATABRICKS_HOST or not DATABRICKS_WAREHOUSE_ID:
        raise RuntimeError(
            "Server is not configured: set DATABRICKS_HOST and DATABRICKS_WAREHOUSE_ID."
        )
    return DatabricksSqlClient(DATABRICKS_HOST, DATABRICKS_WAREHOUSE_ID)


@mcp.tool()
def list_tables(catalog: str, schema: str, ctx: Context) -> dict[str, Any]:
    """List tables and views in a Unity Catalog schema.

    Args:
        catalog: Unity Catalog catalog name.
        schema: Schema (database) name within the catalog.
    """
    try:
        token = _bearer_token(ctx)
        client = _client()
        stmt = (
            f"SELECT table_name, table_type FROM {rulepacks._ident(catalog)}"
            f".information_schema.tables WHERE table_schema = '{schema.replace(chr(39), chr(39) * 2)}' "
            "ORDER BY table_name"
        )
        columns, rows = client.fetch_all(stmt, token)
        tables = [dict(zip(columns, r)) for r in rows]
        return {"catalog": catalog, "schema": schema, "tables": tables, "count": len(tables)}
    except (DatabricksError, _AuthError, RuntimeError) as exc:
        return {"error": str(exc)}


@mcp.tool()
def assess_table(catalog: str, schema: str, table: str, ctx: Context) -> dict[str, Any]:
    """Run a six-dimension data-quality assessment on a Unity Catalog table.

    Scores completeness, uniqueness, validity, timeliness, consistency, and accuracy in
    [0, 1]; the composite is the mean of the assessed dimensions. Known sample tables
    (customers/orders/products) use exact rule packs; other tables are profiled generically.

    Args:
        catalog: Unity Catalog catalog name.
        schema: Schema (database) name within the catalog.
        table: Table or view name to assess.
    """
    try:
        token = _bearer_token(ctx)
        client = _client()
        records_checked, dimensions, used_rulepack = rulepacks.assess(
            client, token, catalog, schema, table)
        composite = scoring.composite([d["score"] for d in dimensions])
        overall = scoring.severity(composite)
        recommendations = _recommendations(dimensions, composite)
        return {
            "table": f"{catalog}.{schema}.{table}",
            "assessed_at": _dt.datetime.now(_dt.timezone.utc).isoformat(),
            "records_checked": records_checked,
            "dimensions": dimensions,
            "composite_score": None if composite is None else round(composite, 4),
            "severity": overall,
            "recommendations": recommendations,
            "method": "rulepack" if used_rulepack else "generic_profile",
        }
    except (DatabricksError, _AuthError, RuntimeError) as exc:
        return {"error": str(exc), "table": f"{catalog}.{schema}.{table}"}


def _recommendations(dimensions: list[dict], composite: float | None) -> list[str]:
    recs = [f"Overall: {scoring.recommend(composite)}"]
    for d in dimensions:
        if d["score"] is not None and d["score"] < 0.95:
            recs.append(f"{d['dimension']}: {scoring.recommend(d['score'])} ({d['finding']})")
    return recs


# Expose the ASGI app for the container entrypoint (uvicorn ... server:app).
app = mcp.streamable_http_app()


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
