# Foundry model deployment (gpt-4.1)

## What it is
A **model deployment** makes a specific model available in your Foundry account for
inference. This solution deploys **`gpt-4.1`** as the agent's reasoning model — it has strong
tool-calling, which the agent relies on to invoke the Databricks MCP tools. Models are
**account-scoped** and shared by the account's projects.

## Prerequisites
- A Foundry account + project ([Foundry account](foundry-account.md)).
- **Quota** for the model in your region. Check under **Quotas** in the Foundry portal or
  `az cognitiveservices usage list`. If `gpt-4.1` quota is unavailable, `gpt-5-mini` is a
  smaller fallback.

## Create it in the portal
1. In the [Foundry portal](https://ai.azure.com), open your project → **Models + endpoints**
   (or **Deployments**).
2. **Deploy model** → **Deploy base model** → select **gpt-4.1** → **Confirm**.
3. Set:
   - **Deployment name:** `<model-deployment-name>` (e.g. `gpt-4.1`).
   - **Deployment type:** **Global Standard**.
   - **Capacity:** e.g. **50** (thousand tokens/min) — raise later if throttled.
4. **Deploy.**

## Bicep / CLI reference
Deployed by [`infra/modules/foundry.bicep`](../../infra/modules/foundry.bicep):
```bicep
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: '<model-deployment-name>'
  sku: { name: 'GlobalStandard', capacity: 50 }
  properties: {
    model: { format: 'OpenAI', name: 'gpt-4.1' }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}
```
CLI equivalent:
```bash
az cognitiveservices account deployment create \
  --resource-group <resource-group> \
  --name <foundry-account> \
  --deployment-name <model-deployment-name> \
  --model-name gpt-4.1 --model-format OpenAI \
  --sku-name GlobalStandard --sku-capacity 50
```

## Verify
- The deployment shows **Succeeded** and **Global Standard**.
- Test it in the **Playground** with a simple prompt.
- Confirm the agent can select this deployment as its model.

## Notes
- `versionUpgradeOption: OnceNewDefaultVersionAvailable` keeps the deployment current as new
  default versions ship.
- Capacity is tokens-per-minute in thousands; monitor and scale to avoid 429s during demos.

## Next
- Build the agent and wire tools: [`/agent`](../../agent),
  [Genie managed MCP](../integration/genie-managed-mcp.md),
  [Unity Catalog Functions managed MCP](../integration/uc-functions-managed-mcp.md).
