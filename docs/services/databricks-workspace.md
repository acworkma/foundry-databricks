# Azure Databricks workspace

## What it is
An **Azure Databricks** workspace is the analytics platform that hosts the data and compute
for this solution. This solution uses the **Premium** SKU because it is required for **Unity
Catalog**, **serverless SQL warehouses**, and the **managed MCP servers** that connect
Databricks to the Foundry agent.

## Prerequisites
- An Azure subscription and permission to create resources in a resource group.
- The `Microsoft.Databricks` resource provider registered in the subscription.
- Quota for the workspace region (default here: **East US 2**).

## Create it in the portal
1. In the [Azure portal](https://portal.azure.com), search **Azure Databricks** → **Create**.
2. **Basics:**
   - **Subscription / Resource group:** `<subscription-id>` / `<resource-group>`.
   - **Workspace name:** `<workspace-name>`.
   - **Region:** `<region>` (e.g. East US 2).
   - **Pricing tier:** **Premium**.
3. Leave networking/encryption at defaults for the demo (harden for production).
4. **Review + create** → **Create**. Provisioning takes a few minutes.
5. Open the resource and click **Launch Workspace**.

## Enable Unity Catalog + a SQL warehouse
1. In the workspace, confirm a **metastore** is attached (Catalog Explorer shows catalogs).
   If not, a workspace/account admin assigns one in the **Account console → Data**.
2. Go to **SQL Warehouses**. A **Serverless Starter Warehouse** usually exists; if not,
   create one (Serverless, Small).
3. Note the warehouse **id** (Connection details) — used by `databricks/run_sql.py`.

> **Default Storage note.** If the metastore uses account-level *Default Storage*, create
> catalogs in **Catalog Explorer → Create catalog → Default storage** (or supply a
> `MANAGED LOCATION` in SQL), then point the repo's `${CATALOG}` at it.

## Enable the Managed MCP Servers preview
The MCP integration is Public Preview and is turned on with a Databricks portal toggle — it
is *not* provisioned by this repo's Bicep. Enable it once per workspace:

1. In the Databricks workspace, click your **username** (top-right corner).
2. Select **Previews** from the menu.
3. Find **Managed MCP Servers** and switch its toggle **On**.

The **Previews** menu and toggles only appear for **workspace admins**. If you don't see
them, ask a workspace admin to enable the preview. Required for both the Genie and Unity
Catalog Functions integration patterns.

## Bicep / CLI reference
Deployed by [`infra/modules/databricks.bicep`](../../infra/modules/databricks.bicep):
```bicep
resource databricks 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: '<workspace-name>'
  location: '<region>'
  sku: { name: 'premium' }
  properties: { managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', '<workspace-name>-managed-rg') }
}
```
CLI equivalent:
```bash
az databricks workspace create \
  --resource-group <resource-group> \
  --name <workspace-name> \
  --location <region> \
  --sku premium
```

## Verify
- **Launch Workspace** succeeds and Catalog Explorer lists catalogs.
- A SQL warehouse can start and run `SELECT 1`.
- Load the sample data per [`/databricks`](../../databricks) and run
  `sql/04_run_assessment.sql` — it should return findings.

## Next
- Load data & functions: [`/databricks`](../../databricks).
- Connect to Foundry: [Genie managed MCP](../integration/genie-managed-mcp.md),
  [Unity Catalog Functions managed MCP](../integration/uc-functions-managed-mcp.md).
