# Azure Storage account

## What it is
An **Azure Storage account** provides durable, general-purpose storage (blobs, files, tables,
queues). In this solution it is a **StorageV2** account used for general artifacts and logs
and as a place to stage data if you extend the demo. It is created with secure defaults
(HTTPS-only, TLS 1.2+).

## Prerequisites
- Permission to create storage accounts and assign roles.
- A globally unique, lowercase storage account name (3–24 chars, letters/numbers).

## Create it in the portal
1. In the [Azure portal](https://portal.azure.com), search **Storage accounts** → **Create**.
2. **Basics:** Resource group `<resource-group>`, Name `<storage-account>`, Region
   `<region>`, **Primary service** = Azure Blob, **Redundancy** = LRS (demo).
3. **Advanced:** keep **Require secure transfer** enabled; **minimum TLS = 1.2**.
4. **Review + create** → **Create**.

## Grant access (RBAC)
Use Azure AD data-plane roles rather than account keys:
- **Storage Blob Data Contributor** for identities that read/write blobs.
```bash
az role assignment create --assignee <principal-id> \
  --role "Storage Blob Data Contributor" \
  --scope <storage-account-resource-id>
```

## Bicep / CLI reference
Deployed by [`infra/modules/storage.bicep`](../../infra/modules/storage.bicep):
```bicep
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '<storage-account>'
  location: '<region>'
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}
```
CLI equivalent:
```bash
az storage account create -g <resource-group> -n <storage-account> \
  -l <region> --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false
```

## Verify
- **Secure transfer required** is **Enabled** and **min TLS = 1.2**.
- **Blob public access** is disabled.
- A principal with **Blob Data Contributor** can create a container; keys are not needed.

## Notes
- Prefer **Azure AD auth** over account keys; rotate keys if you must use them.
- For production, consider **private endpoints** and disabling public network access.

## Next
- Grant the [managed identity](managed-identity.md) the roles it needs on this account.
