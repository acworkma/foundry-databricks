#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Deploy the Data Quality Agent infrastructure to your Azure subscription.
#
# Usage:
#   ./deploy.sh <resource-group> [<location>]
#
# Prerequisites:
#   - Azure CLI (az) logged in:  az login
#   - Permission to create resources and role assignments in the subscription.
#
# Example:
#   ./deploy.sh rg-data-quality-agent eastus2
# ---------------------------------------------------------------------------
set -euo pipefail

RESOURCE_GROUP="${1:-}"
LOCATION="${2:-eastus2}"

if [[ -z "${RESOURCE_GROUP}" ]]; then
  echo "Usage: ./deploy.sh <resource-group> [<location>]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Subscription:  $(az account show --query name -o tsv)"
echo "==> Resource group: ${RESOURCE_GROUP}"
echo "==> Location:       ${LOCATION}"

echo "==> Ensuring resource group exists..."
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none

echo "==> Validating template (what-if)..."
az deployment group what-if \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${SCRIPT_DIR}/main.bicep" \
  --parameters "${SCRIPT_DIR}/main.bicepparam" \
  --parameters location="${LOCATION}"

echo "==> Deploying..."
az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "dqagent-$(date +%Y%m%d%H%M%S)" \
  --template-file "${SCRIPT_DIR}/main.bicep" \
  --parameters "${SCRIPT_DIR}/main.bicepparam" \
  --parameters location="${LOCATION}" \
  --output json | tee "${SCRIPT_DIR}/deployment-outputs.json"

echo "==> Done. Outputs saved to infra/deployment-outputs.json"
