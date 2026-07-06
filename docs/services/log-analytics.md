# Log Analytics workspace

## What it is
A **Log Analytics workspace** is the central destination for logs and metrics in Azure
Monitor. In this solution it provides **observability**: you can route diagnostic settings
from the other services (Databricks, Foundry, Key Vault, Storage) to it and query them with
**KQL**.

## Prerequisites
- Permission to create Log Analytics workspaces.
- `Microsoft.OperationalInsights` provider registered.

## Create it in the portal
1. In the [Azure portal](https://portal.azure.com), search **Log Analytics workspaces** →
   **Create**.
2. **Basics:** Resource group `<resource-group>`, Name `<log-analytics-name>`, Region
   `<region>`.
3. **Review + create** → **Create**.

## Wire up diagnostics (optional but recommended)
For each service you want to observe:
1. Open the resource → **Monitoring → Diagnostic settings** → **Add diagnostic setting**.
2. Select the log/metric categories → **Send to Log Analytics workspace** →
   `<log-analytics-name>`.
3. Save. Query later under the workspace's **Logs** (KQL).

## Bicep / CLI reference
Deployed by [`infra/modules/monitoring.bicep`](../../infra/modules/monitoring.bicep):
```bicep
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '<log-analytics-name>'
  location: '<region>'
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}
```
CLI equivalent:
```bash
az monitor log-analytics workspace create \
  -g <resource-group> -n <log-analytics-name> -l <region>
```

## Verify
- The workspace exists and shows a **Workspace ID**.
- Open **Logs** and run a trivial query, e.g. `Heartbeat | take 5` (populates once sources
  send data).

## Notes
- **Retention** defaults to 30 days here; raise it for production/compliance needs.
- Cost is driven by ingested volume — scope diagnostic settings to what you actually query.

## Next
- Add diagnostic settings on the [Databricks workspace](databricks-workspace.md) and
  [Foundry account](foundry-account.md) to centralize their logs.
