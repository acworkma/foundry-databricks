-- ===========================================================================
-- 02_sample_data.sql
-- Seed synthetic, non-PII sample data with INTENTIONAL quality defects so the
-- agent's assessment produces visible findings across all six dimensions.
--
-- Design:
--   products    -> "healthy" table (scores high)
--   customers   -> "problem" table (completeness, uniqueness, validity, timeliness)
--   orders      -> consistency + accuracy defects (cross-table + business rules)
--   order_items -> supports order-total consistency checks
--
-- Idempotent: tables are dropped and recreated on each run.
-- Placeholders (defaults): ${CATALOG} = datahub_demo, ${SCHEMA} = quality.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- products  (HEALTHY: unique keys, no nulls, valid domains, fresh)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ${CATALOG}.${SCHEMA}.products;
CREATE TABLE ${CATALOG}.${SCHEMA}.products (
  product_id    INT,
  product_name  STRING,
  category      STRING,
  unit_price    DECIMAL(10,2),
  updated_at    TIMESTAMP
) COMMENT 'Product catalog. Reference/healthy table for the quality demo.';

INSERT INTO ${CATALOG}.${SCHEMA}.products VALUES
  (1, 'Standard Widget',  'Widgets',      9.99,  current_timestamp() - INTERVAL 2 DAYS),
  (2, 'Deluxe Widget',    'Widgets',     19.99,  current_timestamp() - INTERVAL 3 DAYS),
  (3, 'Basic Gadget',     'Gadgets',     14.50,  current_timestamp() - INTERVAL 1 DAYS),
  (4, 'Pro Gadget',       'Gadgets',     29.00,  current_timestamp() - INTERVAL 5 DAYS),
  (5, 'Sprocket',         'Components',   3.25,  current_timestamp() - INTERVAL 4 DAYS),
  (6, 'Cog',              'Components',   2.75,  current_timestamp() - INTERVAL 2 DAYS),
  (7, 'Assembly Kit',     'Kits',        49.99,  current_timestamp() - INTERVAL 6 DAYS),
  (8, 'Starter Kit',      'Kits',        24.99,  current_timestamp() - INTERVAL 1 DAYS);

-- ---------------------------------------------------------------------------
-- customers  (PROBLEM table)
--   * Completeness : NULL email, NULL region
--   * Uniqueness   : duplicate customer_id (5 appears twice)
--   * Validity     : malformed email, invalid region code, future signup_date
--   * Timeliness   : last_updated_at is stale for the whole table
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ${CATALOG}.${SCHEMA}.customers;
CREATE TABLE ${CATALOG}.${SCHEMA}.customers (
  customer_id     INT,
  full_name       STRING,
  email           STRING,
  region          STRING,
  signup_date     DATE,
  last_updated_at TIMESTAMP
) COMMENT 'Customer master. Intentionally contains quality defects for the demo.';

INSERT INTO ${CATALOG}.${SCHEMA}.customers VALUES
  (1, 'Customer 001', 'customer001@example.com', 'US-EAST', DATE'2023-01-15', TIMESTAMP'2023-06-01 00:00:00'),
  (2, 'Customer 002', 'customer002@example.com', 'US-WEST', DATE'2023-02-20', TIMESTAMP'2023-06-01 00:00:00'),
  (3, 'Customer 003', NULL,                       'US-EAST', DATE'2023-03-10', TIMESTAMP'2023-06-01 00:00:00'), -- NULL email (completeness)
  (4, 'Customer 004', 'not-an-email',             'US-WEST', DATE'2023-03-12', TIMESTAMP'2023-06-01 00:00:00'), -- invalid email (validity)
  (5, 'Customer 005', 'customer005@example.com', 'US-EAST', DATE'2023-04-01', TIMESTAMP'2023-06-01 00:00:00'),
  (5, 'Customer 005', 'customer005@example.com', 'US-EAST', DATE'2023-04-01', TIMESTAMP'2023-06-01 00:00:00'), -- duplicate PK (uniqueness)
  (6, 'Customer 006', 'customer006@example.com', NULL,      DATE'2023-04-18', TIMESTAMP'2023-06-01 00:00:00'), -- NULL region (completeness)
  (7, 'Customer 007', 'customer007@example.com', 'XX-ZZZZ', DATE'2023-05-02', TIMESTAMP'2023-06-01 00:00:00'), -- invalid region (validity)
  (8, 'Customer 008', 'customer008@example.com', 'US-WEST', DATE'2999-01-01', TIMESTAMP'2023-06-01 00:00:00'), -- future signup_date (validity)
  (9, 'Customer 009', 'customer009@example.com', 'US-EAST', DATE'2023-05-20', TIMESTAMP'2023-06-01 00:00:00'),
  (10,'Customer 010', 'customer010@example.com', 'US-WEST', DATE'2023-05-25', TIMESTAMP'2023-06-01 00:00:00');

-- ---------------------------------------------------------------------------
-- orders  (CONSISTENCY + ACCURACY defects)
--   * Consistency : order references a non-existent customer (999)
--   * Accuracy    : ship_date precedes order_date (business-rule violation)
--   * Validity    : invalid status value ('WRONG')
--   * order_total is cross-checked against order_items in the assessment
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ${CATALOG}.${SCHEMA}.orders;
CREATE TABLE ${CATALOG}.${SCHEMA}.orders (
  order_id     INT,
  customer_id  INT,
  order_date   DATE,
  ship_date    DATE,
  status       STRING,
  order_total  DECIMAL(10,2)
) COMMENT 'Sales orders. Contains cross-table and business-rule defects for the demo.';

INSERT INTO ${CATALOG}.${SCHEMA}.orders VALUES
  (1001, 1,   DATE'2023-05-01', DATE'2023-05-03', 'SHIPPED',   29.98),
  (1002, 2,   DATE'2023-05-02', DATE'2023-05-04', 'SHIPPED',   14.50),
  (1003, 3,   DATE'2023-05-03', DATE'2023-05-01', 'SHIPPED',   19.99), -- ship before order (accuracy)
  (1004, 4,   DATE'2023-05-04', DATE'2023-05-06', 'DELIVERED', 58.00),
  (1005, 999, DATE'2023-05-05', DATE'2023-05-07', 'SHIPPED',   3.25),  -- customer 999 does not exist (consistency)
  (1006, 6,   DATE'2023-05-06', DATE'2023-05-08', 'WRONG',     2.75),  -- invalid status (validity)
  (1007, 7,   DATE'2023-05-07', DATE'2023-05-09', 'PENDING',   99.98),
  (1008, 8,   DATE'2023-05-08', DATE'2023-05-10', 'SHIPPED',   24.99),
  (1009, 9,   DATE'2023-05-09', DATE'2023-05-11', 'DELIVERED', 100.00), -- total != sum(items) (consistency)
  (1010, 10,  DATE'2023-05-10', DATE'2023-05-12', 'SHIPPED',   49.99);

-- ---------------------------------------------------------------------------
-- order_items  (line items used to reconcile order_total)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ${CATALOG}.${SCHEMA}.order_items;
CREATE TABLE ${CATALOG}.${SCHEMA}.order_items (
  order_item_id INT,
  order_id      INT,
  product_id    INT,
  quantity      INT,
  unit_price    DECIMAL(10,2)
) COMMENT 'Order line items. Used for order-total consistency checks.';

INSERT INTO ${CATALOG}.${SCHEMA}.order_items VALUES
  (1, 1001, 1, 1,  9.99),
  (2, 1001, 2, 1, 19.99),
  (3, 1002, 3, 1, 14.50),
  (4, 1003, 2, 1, 19.99),
  (5, 1004, 4, 2, 29.00),
  (6, 1005, 5, 1,  3.25),
  (7, 1006, 6, 1,  2.75),
  (8, 1007, 7, 2, 49.99),
  (9, 1008, 8, 1, 24.99),
  (10,1009, 7, 1, 49.99), -- items sum to 49.99, but order_total says 100.00 (consistency)
  (11,1010, 7, 1, 49.99);
