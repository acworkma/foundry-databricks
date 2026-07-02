# Infrastructure (Bicep)

Provisions the full **Data Quality Agent** environment in your Azure subscription: an Azure
Databricks workspace, a Microsoft Foundry account + project + `gpt-4.1` deployment, a
user-assigned managed identity, Key Vault, Storage, Log Analytics, and least-privilege role
assignments.

## Layout
| Path | Purpose |
|------|---------|
| `main.bicep` | Orchestration template (resource-group scoped). |
| `main.bicepparam` | Parameters — edit these to customize your deployment. |
| `deploy.sh` | Convenience script: creates the RG, runs what-if, deploys, saves outputs. |
| `modules/` | One module per service (databricks, foundry, identity, keyvault, storage, monitoring) + a generic `roleAssignment.bicep`. |

## Prerequisites
- **Azure CLI** logged in: `az login` (and `az account set --subscription <subscription-id>`).
- Permission to create resources **and role assignments** (Owner or Contributor +
  User Access Administrator) on the target subscription/resource group.
- Quota for `gpt-4.1` in your region (default **East US 2**). Check with
  `az cognitiveservices usage list -l <region>`; if unavailable, set `modelName` to a model
  you have quota for (e.g. `gpt-5-mini`).

## Parameters
Edit `main.bicepparam`:
| Parameter | Default | Notes |
|-----------|---------|-------|
| `workloadName` | `dqagent` | Short prefix for resource names (3–12 lowercase alphanumeric). |
| `environmentName` | `demo` | Environment suffix (e.g. dev/test/demo). |
| `modelName` | `gpt-4.1` | Chat model to deploy. |
| `modelCapacity` | `20` | Deployment capacity (thousand tokens/min). |
| `developerPrincipalId` | `''` | Optional object ID to grant **Azure AI Developer** on the Foundry account (find yours: `az ad signed-in-user show --query id -o tsv`). Leave empty to skip. |

## Deploy

### Option 1 — the script (recommended)
```bash
cd infra
./deploy.sh <resource-group> <region>      # e.g. ./deploy.sh rg-data-quality-agent eastus2
```
It creates the resource group, runs a **what-if**, deploys, and writes
`deployment-outputs.json` (git-ignored).

### Option 2 — az CLI directly
```bash
az group create -n <resource-group> -l <region>

az deployment group what-if \
  -g <resource-group> \
  -f infra/main.bicep -p infra/main.bicepparam -p location=<region>

az deployment group create \
  -g <resource-group> \
  -f infra/main.bicep -p infra/main.bicepparam -p location=<region>
```

> Building on **Linux/WSL**? Run the same commands via
> `wsl -e bash -lc "cd infra && ./deploy.sh <resource-group> <region>"`.

## Outputs
The deployment emits the Databricks workspace URL, the Foundry account and project endpoint,
the model deployment name, and the names of the identity, Key Vault, Storage, and Log
Analytics resources. Use these when following the [`/databricks`](../databricks) and
[`/agent`](../agent) steps.

## What this does *not* deploy
The Databricks **managed MCP** preview, the **Genie Space**, and the **Foundry tool
connections** are Public Preview portal steps and are not ARM/Bicep-deployable today. See
[`docs/integration/`](../docs/integration/).

## Clean up
```bash
az group delete -n <resource-group> --yes --no-wait
```

## Notes on the Bicep
- Role assignments live in `modules/roleAssignment.bicep`. Assignment `name`/`scope` cannot
  use other modules' runtime outputs, so resource names are computed as start-time variables
  in `main.bicep` and passed in — this avoids `BCP120` errors.
- The Foundry account uses `Microsoft.CognitiveServices/accounts@2025-06-01` with
  `kind: 'AIServices'` and `allowProjectManagement: true` (the hub-free Foundry model).
