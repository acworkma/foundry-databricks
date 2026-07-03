#!/usr/bin/env python3
"""Run a .sql file against a Databricks SQL warehouse via the Statement
Execution API.

This is a small, dependency-free helper (standard library only) so you can
seed the demo without installing the Databricks CLI or SDK.

Environment variables:
  DATABRICKS_HOST      e.g. https://<workspace-host>.azuredatabricks.net
  DATABRICKS_TOKEN     a Databricks PAT, or an Entra access token for resource
                       2ff814a6-3304-4ab8-85cb-cd0e6f879c1d
  DATABRICKS_WAREHOUSE_ID   the SQL warehouse ID to run against
  DATABRICKS_CATALOG   catalog name to substitute for ${CATALOG} (default datahub_demo)
  DATABRICKS_SCHEMA    schema name to substitute for ${SCHEMA}  (default quality)

Usage:
  python run_sql.py sql/01_setup_catalog.sql sql/02_sample_data.sql ...
  python run_sql.py --show-results sql/04_run_assessment.sql

Flags:
  --show-results (-r)   Print each statement's returned rows as a table. Handy
                        for the assessment queries; defaults to row counts only.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
TOKEN = os.environ["DATABRICKS_TOKEN"]
WAREHOUSE_ID = os.environ["DATABRICKS_WAREHOUSE_ID"]
CATALOG = os.environ.get("DATABRICKS_CATALOG", "datahub_demo")
SCHEMA = os.environ.get("DATABRICKS_SCHEMA", "quality")

API = f"{HOST}/api/2.0/sql/statements"
HEADERS = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def substitute(sql_text):
    """Replace ${CATALOG} / ${SCHEMA} placeholders with configured names."""
    return sql_text.replace("${CATALOG}", CATALOG).replace("${SCHEMA}", SCHEMA)


def split_statements(sql_text):
    """Split a SQL script into individual statements on top-level semicolons.

    Semicolons inside single-quoted string literals are ignored (SQL uses ''
    to escape a quote inside a string). Comment-only fragments are skipped.
    """
    parts = []
    buf = []
    in_string = False
    i = 0
    n = len(sql_text)
    while i < n:
        ch = sql_text[i]
        if in_string:
            buf.append(ch)
            if ch == "'":
                # Doubled '' is an escaped quote, not the end of the string.
                if i + 1 < n and sql_text[i + 1] == "'":
                    buf.append(sql_text[i + 1])
                    i += 2
                    continue
                in_string = False
            i += 1
            continue
        # A -- line comment runs to end of line; copy it verbatim, no splitting.
        if ch == "-" and i + 1 < n and sql_text[i + 1] == "-":
            eol = sql_text.find("\n", i)
            if eol == -1:
                eol = n
            buf.append(sql_text[i:eol])
            i = eol
            continue
        if ch == "'":
            in_string = True
            buf.append(ch)
        elif ch == ";":
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        i += 1
    if buf:
        parts.append("".join(buf))

    statements = []
    for raw in parts:
        # Drop full-line comments and blank lines to test for emptiness.
        meaningful = "\n".join(
            line for line in raw.splitlines() if not line.strip().startswith("--")
        ).strip()
        if meaningful:
            statements.append(raw.strip())
    return statements


def run_statement(stmt):
    body = json.dumps(
        {
            "warehouse_id": WAREHOUSE_ID,
            "statement": stmt,
            "wait_timeout": "50s",
            "on_wait_timeout": "CONTINUE",
        }
    ).encode()
    req = urllib.request.Request(API, data=body, headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        result = json.load(resp)

    statement_id = result.get("statement_id")
    state = result.get("status", {}).get("state")

    # Poll until the statement leaves a running/pending state.
    while state in ("PENDING", "RUNNING"):
        time.sleep(2)
        poll = urllib.request.Request(f"{API}/{statement_id}", headers=HEADERS)
        with urllib.request.urlopen(poll) as resp:
            result = json.load(resp)
        state = result.get("status", {}).get("state")

    if state != "SUCCEEDED":
        err = result.get("status", {}).get("error", {})
        raise RuntimeError(f"Statement failed ({state}): {err.get('message', result)}")
    return result


def format_result_table(result, max_rows=200):
    """Render a statement's result set as a simple text table (stdlib only)."""
    manifest = result.get("manifest", {})
    columns = [c.get("name", "") for c in manifest.get("schema", {}).get("columns", [])]
    rows = result.get("result", {}).get("data_array", []) or []
    if not columns or not rows:
        return ""
    shown = rows[:max_rows]
    widths = [
        max([len(str(columns[i]))] + [len(str(r[i])) for r in shown])
        for i in range(len(columns))
    ]

    def fmt(cells):
        return " | ".join(str(cells[i]).ljust(widths[i]) for i in range(len(columns)))

    lines = [
        "        " + fmt(columns),
        "        " + "-+-".join("-" * w for w in widths),
    ]
    lines += ["        " + fmt(r) for r in shown]
    if len(rows) > max_rows:
        lines.append(f"        ... {len(rows) - max_rows} more row(s)")
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    show_results = False
    files = []
    for arg in args:
        if arg in ("--show-results", "-r"):
            show_results = True
        else:
            files.append(arg)
    if not files:
        print(__doc__)
        sys.exit(1)

    for path in files:
        with open(path, "r", encoding="utf-8") as fh:
            sql_text = substitute(fh.read())
        statements = split_statements(sql_text)
        print(f"==> {path}: {len(statements)} statement(s)")
        for i, stmt in enumerate(statements, 1):
            preview = " ".join(stmt.split())[:70]
            try:
                result = run_statement(stmt)
            except urllib.error.HTTPError as exc:
                print(f"    [{i}] HTTP {exc.code}: {exc.read().decode()[:300]}")
                sys.exit(1)
            except RuntimeError as exc:
                print(f"    [{i}] FAILED: {exc}")
                sys.exit(1)
            rowcount = len(result.get("result", {}).get("data_array", []) or [])
            print(f"    [{i}] OK  {preview}"
                  + (f"  ({rowcount} rows)" if rowcount else ""))
            if show_results and rowcount:
                table = format_result_table(result)
                if table:
                    print(table)

    print("==> Done.")


if __name__ == "__main__":
    main()
