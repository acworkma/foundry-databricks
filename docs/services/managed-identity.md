# User-assigned managed identity

## What it is
A **user-assigned managed identity** is a standalone Azure AD (Entra) identity you can attach
to one or more Azure resources so they authenticate to other services **without secrets**.
This solution provisions one as the recommended **passwordless** building block for
service-to-service auth (e.g. a future custom MCP server calling Databricks, or app code
reading Key Vault).

## Prerequisites
- Permission to create managed identities and assign roles (**User Access Administrator** or
  **Owner** on the target scope for role assignments).

## Create it in the portal
1. In the [Azure portal](https://portal.azure.com), search **Managed Identities** → **Create**.
2. Set **Resource group** `<resource-group>`, **Region** `<region>`, **Name**
   `<managed-identity>`.
3. **Review + create** → **Create**.
4. Copy the **Client ID** and **Object (principal) ID** from the **Overview** — you'll use
   them in role assignments and app config.

## Assign roles (least privilege)
Grant the identity only what it needs, for example:
- **Key Vault Secrets User** on `<key-vault-name>` (read secrets).
- **Storage Blob Data Contributor** on `<storage-account>` (if it reads/writes blobs).
- A Databricks-side grant if it queries Unity Catalog.

## Bicep / CLI reference
Deployed by [`infra/modules/identity.bicep`](../../infra/modules/identity.bicep):
```bicep
resource mi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '<managed-identity>'
  location: '<region>'
}
```
Role assignments are created by
[`infra/modules/roleAssignment.bicep`](../../infra/modules/roleAssignment.bicep) using the
identity's `principalId`. CLI equivalent:
```bash
az identity create -g <resource-group> -n <managed-identity> -l <region>
az role assignment create --assignee <principal-id> \
  --role "Key Vault Secrets User" \
  --scope <key-vault-resource-id>
```

## Verify
- The identity exists with a **Client ID** and **Principal ID**.
- **Access control (IAM)** on target resources lists the expected role assignments.

## Next
- Attach it to a compute resource (e.g. a Container App for the
  [custom MCP server](../integration/custom-mcp-server.md)) via the resource's **Identity**
  blade.
