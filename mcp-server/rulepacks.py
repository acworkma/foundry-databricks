"""Rule packs that turn a table into raw metrics, then into dimension scores.

Two paths, both returning the same shape so the agent output is identical:

* **Known sample tables** (customers / orders / products) reproduce the exact checks
  from ``databricks/sql/03_quality_functions.sql`` so scores match the UC Functions
  baseline (e.g. customers composite ~0.773).
* **Arbitrary tables** are profiled generically from ``DESCRIBE`` output: completeness
  (nulls across all columns), uniqueness (on a detected key), and timeliness (on a
  detected date/timestamp column). Dimensions with no generic rule are *Not Assessed*.
"""
from __future__ import annotations

from typing import Any, Optional

import scoring
from databricks_client import DatabricksSqlClient


def _fqtn(catalog: str, schema: str, table: str) -> str:
    return f"`{_ident(catalog)}`.`{_ident(schema)}`.`{_ident(table)}`"


def _ident(name: str) -> str:
    # Escape backticks in identifiers by doubling them.
    return str(name).replace("`", "``")


def _int(value: Any) -> Optional[int]:
    """Coerce a JSON_ARRAY cell (strings / None) to int."""
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(float(value))


# ---------------------------------------------------------------------------
# Known sample tables
# ---------------------------------------------------------------------------

def _customers(m: dict) -> list[dict]:
    n = _int(m["n"]) or 0
    null_email = _int(m["null_email"]) or 0
    null_region = _int(m["null_region"]) or 0
    dup_ids = _int(m["dup_ids"]) or 0
    bad_email = _int(m["bad_email"]) or 0
    bad_region = _int(m["bad_region"]) or 0
    future_signup = _int(m["future_signup"]) or 0
    signup_after_update = _int(m["signup_after_update"]) or 0
    missing_name = _int(m["missing_name"]) or 0
    age_days = _int(m["age_days"])
    fresh = scoring.freshness_score(age_days, 30)
    return [
        scoring.dimension("completeness", 2 * n, null_email + null_region,
                          scoring.ratio_score(null_email + null_region, 2 * n),
                          f"{null_email} null email(s), {null_region} null region(s)."),
        scoring.dimension("uniqueness", n, dup_ids,
                          scoring.ratio_score(dup_ids, n),
                          f"{dup_ids} duplicate customer_id value(s)."),
        scoring.dimension("validity", 3 * n, bad_email + bad_region + future_signup,
                          scoring.ratio_score(bad_email + bad_region + future_signup, 3 * n),
                          f"{bad_email} malformed email(s), {bad_region} invalid region(s), "
                          f"{future_signup} future signup date(s)."),
        scoring.dimension("timeliness", n, n if (age_days or 0) > 30 else 0, fresh,
                          f"Newest record is {age_days} day(s) old (target 30)."),
        scoring.dimension("consistency", n, signup_after_update,
                          scoring.ratio_score(signup_after_update, n),
                          f"{signup_after_update} record(s) where signup_date is after last_updated_at."),
        scoring.dimension("accuracy", n, missing_name,
                          scoring.ratio_score(missing_name, n),
                          f"{missing_name} record(s) missing a required full_name."),
    ]


def _customers_sql(fqtn: str) -> str:
    return f"""
      SELECT count(*) AS n,
        sum(CASE WHEN email IS NULL THEN 1 ELSE 0 END) AS null_email,
        sum(CASE WHEN region IS NULL THEN 1 ELSE 0 END) AS null_region,
        count(*) - count(DISTINCT customer_id) AS dup_ids,
        sum(CASE WHEN email IS NOT NULL AND email NOT LIKE '%@%.%' THEN 1 ELSE 0 END) AS bad_email,
        sum(CASE WHEN region IS NOT NULL AND region NOT IN ('US-EAST','US-WEST','US-CENTRAL') THEN 1 ELSE 0 END) AS bad_region,
        sum(CASE WHEN signup_date > current_date() THEN 1 ELSE 0 END) AS future_signup,
        sum(CASE WHEN signup_date > to_date(last_updated_at) THEN 1 ELSE 0 END) AS signup_after_update,
        sum(CASE WHEN full_name IS NULL OR trim(full_name) = '' THEN 1 ELSE 0 END) AS missing_name,
        datediff(current_date(), to_date(max(last_updated_at))) AS age_days
      FROM {fqtn}
    """


def _orders(m: dict) -> list[dict]:
    n = _int(m["n"]) or 0
    null_keys = _int(m["null_keys"]) or 0
    dup_ids = _int(m["dup_ids"]) or 0
    bad_status = _int(m["bad_status"]) or 0
    ship_before_order = _int(m["ship_before_order"]) or 0
    orphan_customers = _int(m["orphan_customers"]) or 0
    total_mismatch = _int(m["total_mismatch"]) or 0
    age_days = _int(m["age_days"])
    fresh = scoring.freshness_score(age_days, 30)
    return [
        scoring.dimension("completeness", n, null_keys,
                          scoring.ratio_score(null_keys, n),
                          f"{null_keys} record(s) missing customer_id or order_date."),
        scoring.dimension("uniqueness", n, dup_ids,
                          scoring.ratio_score(dup_ids, n),
                          f"{dup_ids} duplicate order_id value(s)."),
        scoring.dimension("validity", n, bad_status,
                          scoring.ratio_score(bad_status, n),
                          f"{bad_status} order(s) with an invalid status value."),
        scoring.dimension("timeliness", n, n if (age_days or 0) > 30 else 0, fresh,
                          f"Newest order is {age_days} day(s) old (target 30)."),
        scoring.dimension("consistency", n, orphan_customers + total_mismatch,
                          scoring.ratio_score(orphan_customers + total_mismatch, n),
                          f"{orphan_customers} order(s) reference a missing customer; "
                          f"{total_mismatch} order(s) where order_total != sum(line items)."),
        scoring.dimension("accuracy", n, ship_before_order,
                          scoring.ratio_score(ship_before_order, n),
                          f"{ship_before_order} order(s) where ship_date precedes order_date."),
    ]


def _orders_sql(catalog: str, schema: str) -> str:
    orders = _fqtn(catalog, schema, "orders")
    customers = _fqtn(catalog, schema, "customers")
    order_items = _fqtn(catalog, schema, "order_items")
    return f"""
      WITH o AS (
        SELECT count(*) AS n,
          sum(CASE WHEN customer_id IS NULL OR order_date IS NULL THEN 1 ELSE 0 END) AS null_keys,
          count(*) - count(DISTINCT order_id) AS dup_ids,
          sum(CASE WHEN status NOT IN ('PENDING','SHIPPED','DELIVERED','CANCELLED') THEN 1 ELSE 0 END) AS bad_status,
          sum(CASE WHEN ship_date < order_date THEN 1 ELSE 0 END) AS ship_before_order,
          datediff(current_date(), max(order_date)) AS age_days
        FROM {orders}
      ),
      ref AS (
        SELECT sum(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END) AS orphan_customers
        FROM {orders} ord LEFT JOIN {customers} c ON ord.customer_id = c.customer_id
      ),
      rec AS (
        SELECT count(*) AS total_mismatch FROM (
          SELECT ord.order_id, ord.order_total,
                 coalesce(sum(oi.quantity * oi.unit_price), 0) AS items_total
          FROM {orders} ord LEFT JOIN {order_items} oi ON ord.order_id = oi.order_id
          GROUP BY ord.order_id, ord.order_total
          HAVING abs(ord.order_total - coalesce(sum(oi.quantity * oi.unit_price), 0)) > 0.01
        )
      )
      SELECT o.n, o.null_keys, o.dup_ids, o.bad_status, o.ship_before_order, o.age_days,
             ref.orphan_customers, rec.total_mismatch
      FROM o, ref, rec
    """


def _products(m: dict) -> list[dict]:
    n = _int(m["n"]) or 0
    null_cells = _int(m["null_cells"]) or 0
    dup_ids = _int(m["dup_ids"]) or 0
    invalid_vals = _int(m["invalid_vals"]) or 0
    blank_name = _int(m["blank_name"]) or 0
    age_days = _int(m["age_days"])
    fresh = scoring.freshness_score(age_days, 30)
    return [
        scoring.dimension("completeness", n, null_cells,
                          scoring.ratio_score(null_cells, n),
                          f"{null_cells} record(s) with a null required field."),
        scoring.dimension("uniqueness", n, dup_ids,
                          scoring.ratio_score(dup_ids, n),
                          f"{dup_ids} duplicate product_id value(s)."),
        scoring.dimension("validity", n, invalid_vals,
                          scoring.ratio_score(invalid_vals, n),
                          f"{invalid_vals} record(s) with non-positive price or invalid category."),
        scoring.dimension("timeliness", n, n if (age_days or 0) > 30 else 0, fresh,
                          f"Newest record is {age_days} day(s) old (target 30)."),
        scoring.dimension("consistency", n, None, None,
                          "No cross-table consistency rule defined for products; not assessed."),
        scoring.dimension("accuracy", n, blank_name,
                          scoring.ratio_score(blank_name, n),
                          f"{blank_name} record(s) with a blank product_name."),
    ]


def _products_sql(fqtn: str) -> str:
    return f"""
      SELECT count(*) AS n,
        sum(CASE WHEN product_name IS NULL OR category IS NULL OR unit_price IS NULL THEN 1 ELSE 0 END) AS null_cells,
        count(*) - count(DISTINCT product_id) AS dup_ids,
        sum(CASE WHEN unit_price <= 0 OR category NOT IN ('Widgets','Gadgets','Components','Kits') THEN 1 ELSE 0 END) AS invalid_vals,
        sum(CASE WHEN trim(product_name) = '' THEN 1 ELSE 0 END) AS blank_name,
        datediff(current_date(), to_date(max(updated_at))) AS age_days
      FROM {fqtn}
    """


_KNOWN = {
    "customers": (_customers_sql, _customers),
    "products": (_products_sql, _products),
}


# ---------------------------------------------------------------------------
# Generic profiler for arbitrary tables
# ---------------------------------------------------------------------------

_DATE_TYPES = ("date", "timestamp", "timestamp_ntz")


def _describe(client: DatabricksSqlClient, token: str, fqtn: str) -> list[tuple[str, str]]:
    """Return [(col_name, data_type), ...] from DESCRIBE, dropping partition metadata."""
    _cols, rows = client.fetch_all(f"DESCRIBE {fqtn}", token)
    out = []
    for row in rows:
        name = (row[0] or "").strip()
        dtype = (row[1] or "").strip().lower() if len(row) > 1 else ""
        if not name or name.startswith("#"):
            break  # partition-info section follows
        out.append((name, dtype))
    return out


def _pick_key(columns: list[tuple[str, str]]) -> Optional[str]:
    names = [c[0] for c in columns]
    for n in names:
        if n.lower() == "id":
            return n
    for n in names:
        if n.lower().endswith("_id"):
            return n
    return names[0] if names else None


def _pick_date_column(columns: list[tuple[str, str]]) -> Optional[str]:
    dates = [n for n, t in columns if t.split("(")[0] in _DATE_TYPES]
    if not dates:
        return None
    for pref in ("updated", "_at", "date", "modified", "created"):
        for n in dates:
            if pref in n.lower():
                return n
    return dates[0]


def _generic(client: DatabricksSqlClient, token: str, catalog: str, schema: str,
             table: str) -> tuple[int, list[dict]]:
    fqtn = _fqtn(catalog, schema, table)
    columns = _describe(client, token, fqtn)
    key = _pick_key(columns)
    date_col = _pick_date_column(columns)

    selects = ["count(*) AS n"]
    for i, (name, _t) in enumerate(columns):
        selects.append(f"sum(CASE WHEN `{_ident(name)}` IS NULL THEN 1 ELSE 0 END) AS null_{i}")
    if key:
        selects.append(f"count(*) - count(DISTINCT `{_ident(key)}`) AS dup_key")
    if date_col:
        selects.append(
            f"datediff(current_date(), to_date(max(`{_ident(date_col)}`))) AS age_days")
    m = client.fetch_one(f"SELECT {', '.join(selects)} FROM {fqtn}", token) or {}

    n = _int(m.get("n")) or 0
    ncols = len(columns)
    total_nulls = sum((_int(m.get(f"null_{i}")) or 0) for i in range(ncols))

    dims = [
        scoring.dimension(
            "completeness", n * ncols, total_nulls,
            scoring.ratio_score(total_nulls, n * ncols),
            f"{total_nulls} null cell(s) across {ncols} column(s) x {n} row(s)."),
    ]
    if key:
        dup_key = _int(m.get("dup_key")) or 0
        dims.append(scoring.dimension(
            "uniqueness", n, dup_key, scoring.ratio_score(dup_key, n),
            f"{dup_key} duplicate value(s) in detected key column '{key}'."))
    else:
        dims.append(scoring.dimension(
            "uniqueness", n, None, None,
            "No key column detected; uniqueness not assessed."))

    dims.append(scoring.dimension(
        "validity", n, None, None,
        "No generic validity rule for an arbitrary table; not assessed. "
        "Add a rule pack to enable."))

    if date_col:
        age_days = _int(m.get("age_days"))
        fresh = scoring.freshness_score(age_days, 30)
        dims.append(scoring.dimension(
            "timeliness", n, n if (age_days or 0) > 30 else 0, fresh,
            f"Newest '{date_col}' is {age_days} day(s) old (target 30)."))
    else:
        dims.append(scoring.dimension(
            "timeliness", n, None, None,
            "No date/timestamp column detected; timeliness not assessed."))

    dims.append(scoring.dimension(
        "consistency", n, None, None,
        "No cross-table rule known for an arbitrary table; not assessed."))
    dims.append(scoring.dimension(
        "accuracy", n, None, None,
        "No business-rule pack for an arbitrary table; not assessed."))
    return n, dims


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def assess(client: DatabricksSqlClient, token: str, catalog: str, schema: str,
           table: str) -> tuple[int, list[dict], bool]:
    """Return (records_checked, dimensions, used_known_rulepack)."""
    key = table.lower()
    if key in _KNOWN:
        sql_fn, map_fn = _KNOWN[key]
        stmt = sql_fn(_fqtn(catalog, schema, table))
        m = client.fetch_one(stmt, token) or {}
        dims = map_fn(m)
        return _int(m.get("n")) or 0, dims, True
    if key == "orders":
        m = client.fetch_one(_orders_sql(catalog, schema), token) or {}
        dims = _orders(m)
        return _int(m.get("n")) or 0, dims, True
    n, dims = _generic(client, token, catalog, schema, table)
    return n, dims, False
