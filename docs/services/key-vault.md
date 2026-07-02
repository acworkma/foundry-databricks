# Azure Key Vault

## What it is
**Azure Key Vault** securely stores secrets, keys, and certificates. In this solution it
holds any connection secrets the solution needs (for example a Databricks token, if you
choose token auth instead of managed identity). The vault uses **Azure RBAC** for data-plane
authorization (not legacy access policies).

## Prerequisites
- Permission to create Key Vaults and assign roles.
- A globally unique vault name.

## Create it in the portal
1. In the [Azure portal](https://portal.azure.com), search **Key Vaults** → **Create**.
2. **Basics:** Resource group `<resource-group>`, Name `<key-vault-name>`, Region `<region>`.
3. **Access configuration:** choose **Azure role-based access control**.
4. **Review + create** → **Create**.

## Grant access (RBAC)
Assign data-plane roles to the identities that need them:
- **Key Vault Secrets Officer** — to create/manage secrets (you, during setup).
- **Key Vault Secrets User** — to read secrets at runtime (the managed identity / app).

```bash
az role assignment create --assignee <principal-id> \
  --role "Key Vault Secrets User" \
  --scope <key-vault-resource-id>
```

## Store a secret (example)
```bash
az keyvault secret set --vault-name <key-vault-name> \
  --name databricks-host --value "https://<databricks-host>"
```

## Bicep / CLI reference
Deployed by [`infra/modules/keyvault.bicep`](../../infra/modules/keyvault.bicep):
```bicep
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '<key-vault-name>'
  location: '<region>'
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}
```

## Verify
- The vault shows **Permission model = Azure role-based access control**.
- A principal with **Secrets User** can read a test secret; one without cannot.

## Notes
- Prefer **managed identity** over stored tokens where possible — then the vault holds fewer
  or no long-lived secrets.
- For production, enable **purge protection** and consider **private endpoints**.

## Next
- Grant the [managed identity](managed-identity.md) **Key Vault Secrets User**.
