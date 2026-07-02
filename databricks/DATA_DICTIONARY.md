# DataHub sample dataset — data dictionary

Synthetic, **non-PII / non-PHI** data created by `sql/02_sample_data.sql`. Every value is
fabricated. The dataset is deliberately small so the assessment output is easy to read, and
it contains **known, intentional defects** so each of the six quality dimensions produces a
visible finding.

Default location: `datahub_demo.quality` (override with `${CATALOG}` / `${SCHEMA}`).

## Six quality dimensions

| Dimension | Definition used here |
|-----------|----------------------|
| **Completeness** | Required fields are populated (not null/blank). |
| **Uniqueness** | Primary keys / business keys are not duplicated. |
| **Validity** | Values match the expected format and domain (e.g. email shape, allowed status codes, sensible dates). |
| **Timeliness** | Data is recent relative to an expected refresh target. |
| **Consistency** | Values agree across tables and reconcile (referential integrity, totals). |
| **Accuracy** | Values obey business rules (e.g. ship date not before order date). |

## Tables

### `products` — healthy baseline
| Column | Type | Notes |
|--------|------|-------|
| `product_id` | INT | Unique product key. |
| `product_name` | STRING | Never null/blank. |
| `category` | STRING | One of `Widgets`, `Gadgets`, `Components`, `Kits`. |
| `unit_price` | DECIMAL(10,2) | Positive. |
| `updated_at` | TIMESTAMP | Recent (relative to run time). |

**Seeded defects:** none. This is the "good" table and should score ~1.0.

### `customers` — problem table
| Column | Type | Notes |
|--------|------|-------|
| `customer_id` | INT | Business key (contains a duplicate). |
| `full_name` | STRING | Required. |
| `email` | STRING | Some null / malformed. |
| `region` | STRING | Expected domain: `US-EAST`, `US-WEST`, `US-CENTRAL`. |
| `signup_date` | DATE | One value is in the far future. |
| `last_updated_at` | TIMESTAMP | Intentionally stale for the whole table. |

**Seeded defects:**
- *Completeness* — a null `email` and a null `region`.
- *Uniqueness* — `customer_id = 5` appears twice.
- *Validity* — a malformed email (`not-an-email`), an out-of-domain region (`XX-ZZZZ`), and a future `signup_date` (`2999-01-01`).
- *Timeliness* — `last_updated_at` is old, so the table reads as stale.

### `orders` — cross-table & business-rule defects
| Column | Type | Notes |
|--------|------|-------|
| `order_id` | INT | Unique order key. |
| `customer_id` | INT | Should reference `customers`. |
| `order_date` | DATE | |
| `ship_date` | DATE | Should not precede `order_date`. |
| `status` | STRING | Expected domain: `PENDING`, `SHIPPED`, `DELIVERED`, `CANCELLED`. |
| `order_total` | DECIMAL(10,2) | Should equal the sum of its line items. |

**Seeded defects:**
- *Consistency* — order `1005` references `customer_id = 999` (does not exist); order `1009` has `order_total` that does not equal the sum of its `order_items`.
- *Validity* — order `1006` has status `WRONG`.
- *Accuracy* — order `1003` has `ship_date` before `order_date`.
- *Timeliness* — order dates are old, so the table reads as stale.

### `order_items` — supporting table
| Column | Type | Notes |
|--------|------|-------|
| `order_item_id` | INT | Unique line-item key. |
| `order_id` | INT | References `orders`. |
| `product_id` | INT | References `products`. |
| `quantity` | INT | |
| `unit_price` | DECIMAL(10,2) | |

Used to reconcile `orders.order_total` against `sum(quantity * unit_price)` for the
consistency check. Line items for order `1009` sum to less than its stated total.

## Why some checks are per-table

Unity Catalog SQL functions cannot execute dynamic SQL, so a single "assess any table"
function is not possible in pure SQL. The repo ships explicit `assess_customers`,
`assess_orders`, and `assess_products` functions. For **arbitrary** tables, use the Genie
Space (Pattern A) or a custom MCP server (Pattern E), both of which can generate SQL
dynamically.
