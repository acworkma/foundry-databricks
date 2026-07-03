# Sample prompts

Prompts to exercise the Data Quality Agent once the Databricks tools are connected. The
first group works against the seeded demo tables via the Unity Catalog Functions tool;
the second group shows natural-language questions routed to the Genie Space.

## Governed function calls (demo tables)

- "Assess the quality of the customers table and give me the composite score and severity."
- "Score the orders table across all six dimensions and list the top issues."
- "Is the products table healthy? Show the per-dimension breakdown."
- "Compare the data quality of customers vs products and tell me which is riskier and why."
- "Give me the customers assessment as JSON."
- "Which table in the demo schema has the worst timeliness score?"

Expected behavior: the agent calls `assess_customers` / `assess_orders` / `assess_products`,
computes the composite with `dq_composite`, classifies it with `dq_severity`, and returns a
scored report. `products` should come back Healthy; `customers` and `orders` should surface
findings and land in the High Risk / Needs Attention range.

## Natural language via Genie

- "How many customers are missing an email address?"
- "Are there any duplicate customer IDs?"
- "Show me orders whose total does not match the sum of their line items."
- "Which orders reference a customer that doesn't exist?"
- "What's the newest order date, and how stale is the orders table?"
- "List orders where the ship date is before the order date."

Expected behavior: Genie translates each question into governed SQL over the sample tables
and returns rows; the agent summarizes them and maps them back to the relevant quality
dimension.

## End-to-end demo script

1. "Assess the products table." → Healthy baseline (~1.0).
2. "Now assess customers." → High Risk; call out completeness, uniqueness, validity,
   timeliness.
3. "Why is the orders table risky?" → consistency (orphan customer, total mismatch),
   validity (bad status), accuracy (ship before order).
4. "Give me a one-paragraph executive summary and the three highest-priority fixes."
