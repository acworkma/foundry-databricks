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
- Roles: **Azure AI Developer** on the project to create agents; a Databricks user/service
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
can call the `assess_*` functions and scalar scorers.

### 3. Add the Genie tool
Follow [`docs/integration/genie-managed-mcp.md`](../docs/integration/genie-managed-mcp.md)
to add `https://<databricks-host>/api/2.0/mcp/genie/<genie-space-id>` so the agent can ask
natural-language questions about any table in the space.

### 4. Test
Open the agent playground and run the prompts in `sample-prompts.md`. Confirm:
- `products` returns **Healthy** (~1.0).
- `customers` and `orders` return findings and land in **High Risk / Needs Attention**.
- The agent cites real counts (it should be calling tools, not guessing).

## Notes
- Genie in preview is rate-limited (about 5 questions/minute) — prefer the deterministic
  Unity Catalog functions for the demo tables and use Genie for ad-hoc questions.
- Authentication to Databricks uses OAuth identity passthrough; a managed (Entra) connection
  is recommended. See the pattern pages for the connection setup.
