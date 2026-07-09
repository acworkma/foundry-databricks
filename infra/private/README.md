# Private-networking infrastructure (Bicep)

Bicep for the **private** Data Quality Agent build — the two managed MCP paths (Unity Catalog
Functions + Genie) running with **no public network access** on serverless SQL (**Option A**).
Read the guide first: [`docs/private-networking.md`](../../docs/private-networking.md).

These templates assume an **existing shared hub** (VNet, private-endpoint subnet, DNS resolver,
and most `privatelink.*` zones). They deploy the Databricks-specific pieces and the Foundry
project as a **spoke** that consumes that hub. Adjust names, address prefixes, and resource
IDs to your environment — all example values are illustrative placeholders.

## Layout

| Path | Scope | Purpose |
|------|-------|---------|
| `dns-zones.bicep` | Hub RG | Net-new private DNS zones `privatelink.azuredatabricks.net` + `privatelink.dfs.core.windows.net`, linked to the shared VNet. |
| `databricks-subnets.bicep` | Hub RG | Two delegated host/container subnets (+ shared NSG) for Databricks VNet injection. |
| `databricks-workspace.bicep` | Spoke RG | Premium, VNet-injected workspace with `publicNetworkAccess=Disabled`; `databricks_ui_api` + `browser_authentication` front-end private endpoints. |
| `uc-storage.bicep` | Spoke RG | Unity Catalog managed storage (ADLS Gen2) + Access Connector; blob + dfs private endpoints; toggle `storagePublicNetworkAccess`. |
| `foundry/main.bicep` | Foundry RG | Orchestrates the Foundry **project** onto an existing private account. |
| `foundry/project.bicep` | Foundry RG | Project (system-assigned MI) + project-unique connections to shared Search/Storage/Cosmos. |
| `foundry/rbac-account.bicep` | Foundry RG | Account-scoped role assignments for the project identity. |
| `foundry/capability-host.bicep` | Foundry RG | Capability host (Agents) for the project. |
| `foundry/format-workspace-id.bicep` | — | Formats the project `internalId` into a GUID for scoped role assignments. |
| `foundry/rbac-container.bicep` | Foundry RG | Container/data-plane role assignments (blob data owner condition + Cosmos SQL role). |

## Deploy order

1. **`dns-zones.bicep`** → hub RG (only the two Databricks zones are typically net-new).
2. **`databricks-subnets.bicep`** → hub RG (host subnet, then container subnet — subnet writes
   on one VNet are serialized).
3. **`databricks-workspace.bicep`** → spoke RG (front-end Private Link; public access off).
4. **`uc-storage.bicep`** → spoke RG (deploy with `storagePublicNetworkAccess=Enabled`, flip to
   `Disabled` after Step 6 below).
5. **NCC (out-of-band, not Bicep)** — create a Network Connectivity Config, add private-endpoint
   rules to the UC storage (`blob` + `dfs`), approve the managed private endpoints, and bind the
   NCC to the workspace. This is an **account-level** operation.
6. Set `storagePublicNetworkAccess=Disabled` and redeploy `uc-storage.bicep` once the NCC
   private path is validated.
7. **`foundry/main.bicep`** → Foundry RG (project + RBAC + capability host).

```bash
# Examples — run via WSL/Linux. Substitute your own names/IDs.
az deployment group create -g <hub-rg> \
  -f infra/private/dns-zones.bicep -p sharedVnetId=<shared-vnet-resource-id>

az deployment group create -g <hub-rg> \
  -f infra/private/databricks-subnets.bicep \
  -p sharedVnetName=<shared-vnet> location=<region>

az deployment group create -g <spoke-rg> \
  -f infra/private/databricks-workspace.bicep \
  -p name=<workspace-name> location=<region> \
     customVirtualNetworkId=<shared-vnet-resource-id> \
     customPublicSubnetName=snet-databricks-host \
     customPrivateSubnetName=snet-databricks-container \
     privateEndpointSubnetId=<pe-subnet-resource-id> \
     databricksDnsZoneId=<azuredatabricks-dns-zone-id>

az deployment group create -g <foundry-rg> \
  -f infra/private/foundry/main.bicep \
  -p accountName=<foundry-account> projectName=<project-name> \
     aiSearchName=<search> cosmosDbName=<cosmos> storageName=<storage>
```

## Notes

- **Why VNet injection for a serverless build?** Disabling public network access on Azure
  Databricks requires an injected workspace, so the host/container subnets exist even though
  serverless is the primary compute. Serverless egress is made private separately by the **NCC**
  (Step 5).
- **Bicep module boundaries (Foundry).** A role-assignment `name`/`scope` cannot reference
  another resource's runtime `identity.principalId` / `properties.internalId` in the same
  deployment (`BCP120`). The `foundry/` set is split into modules that take the project
  principal ID and workspace GUID as **parameters**, mirroring the account's module ordering.
- **Connection namespace.** Foundry connection names are unique within the **account**; on a
  shared account the project uses project-unique connection names that still target the shared
  Search/Storage/Cosmos resources.
- **Not Bicep-deployable (Public Preview / portal):** the NCC and its rules, the Managed MCP
  Servers preview, the Genie space, and the agent's MCP tool connections. See
  [`docs/private-networking.md`](../../docs/private-networking.md) and
  [`docs/integration/`](../../docs/integration/).
