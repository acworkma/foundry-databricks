# Foundry agent — build guide

How to build the **Data Quality Agent** in Microsoft Foundry and connect it to Azure
Databricks. The agent uses your `gpt-4.1` deployment as the reasoning model and reaches
Databricks through managed **MCP** tools.

> The Databricks managed MCP servers and the Genie-in-Foundry tool connection are **Public
> Preview**. Steps below are portal ("click-ops") because these connections are not fully
> ARM/Bicep-deployable today. Values in angle brackets are placeholders — substitute your
> own.

## Files in this folder
| File | Use |
|------|-----|
| `instructions.md` | Paste into the agent's **Instructions** / system prompt. |
| `SKILL.md` | The portable skill definition (scoring model + output contract). Attach as a knowledge file or fold into instructions. |
| `sample-prompts.md` | Prompts to validate the agent end to end. |

## Prerequisites
- Infrastructure deployed (see [`/infra`](../infra)) — a Foundry account + project and a
  `gpt-4.1` model deployment.
- Databricks sample data + functions loaded (see [`/databricks`](../databricks)).
- A **Genie Space** over the sample tables (see
  [`docs/integration/genie-managed-mcp.md`](../docs/integration/genie-managed-mcp.md)).
- Roles: **Foundry User** on the project to create agents; a Databricks user/service
  principal that can read the target catalog.

## Steps

### 1. Create the agent
1. Open the **Foundry portal** → your project → **Agents** → **New agent**.
2. Set the **model** to your `gpt-4.1` deployment.
3. Paste the contents of `instructions.md` into **Instructions**.
4. (Optional) Upload `SKILL.md` as a knowledge file so the scoring model travels with the
   agent.

### 2. Add the Unity Catalog Functions tool
Follow [`docs/integration/uc-functions-managed-mcp.md`](../docs/integration/uc-functions-managed-mcp.md)
to add the managed MCP server
`https://<databricks-host>/api/2.0/mcp/functions/<catalog>/<schema>` as a tool so the agent
can call the `assess_*` functions and scalar scorers. This tool authenticates with **Microsoft
Entra** using the Foundry **project's managed identity** — a prerequisite is granting that
identity in Databricks (run
[`databricks/sql/05_grant_mcp_identity.sql`](../databricks/sql/05_grant_mcp_identity.sql)).

### 3. Add the Genie tool
Follow [`docs/integration/genie-managed-mcp.md`](../docs/integration/genie-managed-mcp.md)
to add `https://<databricks-host>/api/2.0/mcp/genie/<genie-space-id>` so the agent can ask
natural-language questions about any table in the space.

### 4. Test
Open the agent playground and run the prompts in `sample-prompts.md`. Confirm:
- `products` returns **Healthy** (~1.0).
- `customers` and `orders` return findings and land in **High Risk** (~0.77).
- The agent cites real counts (it should be calling tools, not guessing).
- **Routing is correct:** open **Traces** and check the tool span — scoring prompts show
  **`databricks-uc-functions`**, ad-hoc questions show **`AzureDatabricksGenie`**. If a scoring
  prompt goes to Genie, tighten the routing rules in `instructions.md`.

## Notes
- Genie in preview is rate-limited (about 5 questions/minute) — prefer the deterministic
  Unity Catalog functions for the demo tables and use Genie for ad-hoc questions.
- **Authentication differs per tool.** The Unity Catalog Functions tool uses **Microsoft Entra
  with the project managed identity** (a service identity — no consent prompt); grant that
  identity in Databricks first (see step 2). Genie uses **user identity passthrough** with a
  one-time **Open consent → sign in → Approve**. See the pattern pages for details.
- **Tool selection** is driven by the agent's `instructions.md` plus each tool's name and
  description (including the UC function `COMMENT` strings). With two data tools attached, the
  explicit routing rules in `instructions.md` are what make the choice deterministic.
