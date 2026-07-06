# Sample prompts

Prompts to exercise the Data Quality Agent once both Databricks tools are connected. The agent
holds two tools and routes between them based on its [Instructions](instructions.md):

- **MCP prompts (Unity Catalog Functions)** — governed, deterministic scoring of the demo
  tables. These call `assess_customers` / `assess_orders` / `assess_products`.
- **Genie prompts** — open-ended natural-language questions answered by the Genie Space.

To confirm which tool ran, open **Traces** on a response and check the tool span: it reads
**`databricks-uc-functions`** for the MCP path or **`AzureDatabricksGenie`** for the Genie path.

## MCP prompts — Unity Catalog Functions (governed scoring)

These should route to the `assess_*` functions:

- "Assess the customers table and give me the composite score and severity."
- "Score the orders table across all six dimensions and list the top issues."
- "Is the products table healthy? Show the per-dimension breakdown."
- "Compare the data quality of customers vs products and tell me which is riskier and why."
- "Give me the customers assessment as JSON."
- "Which of customers, orders, or products has the worst timeliness score?"

Expected behavior: the trace shows **`databricks-uc-functions`**. `products` comes back
**Healthy** (~1.0); `customers` and `orders` land in **High Risk** (~0.77) with concrete
findings, and **Timeliness** is the critical dimension (stale sample data). Because the tool
uses a service identity (Microsoft Entra + project managed identity), there is **no consent
prompt**.

## Genie prompts — natural language (ad-hoc questions)

These have no dedicated `assess_*` function, so they should route to Genie:

- "Which product category has the most orders, and what's the total revenue for it?"
- "How many customers are missing an email address?"
- "Are there any duplicate customer IDs?"
- "Show me orders whose total does not match the sum of their line items."
- "Which orders reference a customer that doesn't exist?"
- "List orders where the ship date is before the order date."

Expected behavior: the trace shows **`AzureDatabricksGenie`**. Genie translates each question
into governed SQL, returns rows, and the agent summarizes them. First use triggers Genie's
one-time **Open consent → sign in → Approve** flow (user identity passthrough).

## End-to-end demo script

1. "Assess the products table." → **UC function**, Healthy baseline (~1.0).
2. "Now assess customers." → **UC function**, High Risk; call out completeness, uniqueness,
   validity, timeliness.
3. "Why is the orders table risky?" → **UC function**, consistency (orphan customer, total
   mismatch), validity (bad status), accuracy (ship before order).
4. "Which product category has the most orders?" → **Genie**, shows the ad-hoc path.
5. "Give me a one-paragraph executive summary and the three highest-priority fixes."
