# Managed identity

## User-assigned managed identity

### What it is
A **user-assigned managed identity** is a standalone Azure AD (Entra) identity you can attach
to one or more Azure resources so they authenticate to other services **without secrets**.
This solution provisions one as the recommended **passwordless** building block for
service-to-service auth (e.g. a future custom MCP server calling Databricks, or app code
reading Key Vault).

### Prerequisites
- Permission to create managed identities and assign roles (**User Access Administrator** or
  **Owner** on the target scope for role assignments).

### Create it in the portal
1. In the [Azure portal](https://portal.azure.com), search **Managed Identities** → **Create**.
2. Set **Resource group** `<resource-group>`, **Region** `<region>`, **Name**
   `<managed-identity>`.
3. **Review + create** → **Create**.
4. Copy the **Client ID** and **Object (principal) ID** from the **Overview** — you'll use
   them in role assignments and app config.

### Assign roles (least privilege)
Grant the identity only what it needs, for example:
- **Key Vault Secrets User** on `<key-vault-name>` (read secrets).
- **Storage Blob Data Contributor** on `<storage-account>` (if it reads/writes blobs).
- A Databricks-side grant if it queries Unity Catalog.

### Bicep / CLI reference
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

### Verify
- The identity exists with a **Client ID** and **Principal ID**.
- **Access control (IAM)** on target resources lists the expected role assignments.

### Next
- Attach it to a compute resource (e.g. a Container App for the
  [custom MCP server](../integration/custom-mcp-server.md)) via the resource's **Identity**
  blade.

---

## Foundry project managed identity → Databricks (UC Functions MCP)

The user-assigned identity above is the building block for **custom** service-to-service auth.
The **Unity Catalog Functions managed MCP** tool uses a different, built-in identity: the
Foundry **project's own system-assigned managed identity**. This is the cleanest way to
authenticate that tool — a **service identity**, so there is **no user sign-in, no OAuth app,
and no personal access token** (contrast with Genie, which uses user identity passthrough and a
one-time consent).

### 1. Find the project identity
In the Azure portal, open your **Foundry project** resource → **Identity → System assigned**.
Note its **Application (client) ID** — call it `<project-mi-app-id>`. (Every Foundry project
gets a system-assigned managed identity automatically.)

### 2. Register it in Databricks and grant access
1. As a Databricks workspace admin: **Settings → Identity and access → Service principals →
   Add service principal → Microsoft Entra managed**, paste `<project-mi-app-id>`, and grant
   **Workspace access**.
2. Grant Unity Catalog privileges (and the ownership-chaining fix) by running
   [`databricks/sql/05_grant_mcp_identity.sql`](../../databricks/sql/05_grant_mcp_identity.sql).

### 3. Configure the tool in Foundry
When adding the MCP tool (see
[uc-functions-managed-mcp.md](../integration/uc-functions-managed-mcp.md)), set:

| Field | Value |
|-------|-------|
| **Authentication** | Microsoft Entra |
| **Type** | Project Managed Identity |
| **Audience** | `2ff814a6-3304-4ab8-85cb-cd0e6f879c1d` (Azure Databricks' fixed first-party Entra app ID — same in every tenant) |

Because it is a service identity, tool calls run **without a consent prompt**.
