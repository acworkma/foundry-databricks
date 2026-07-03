// ---------------------------------------------------------------------------
// Key Vault — RBAC-authorized secret store (e.g. for a custom MCP server's
// Databricks token). No access policies; uses Azure RBAC.
// ---------------------------------------------------------------------------
@description('Azure region for the vault.')
param location string

@description('Globally unique Key Vault name (3-24 alphanumeric/hyphen).')
param name string

@description('Tenant ID for the vault.')
param tenantId string = subscription().tenantId

@description('Tags applied to the resource.')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

output id string = keyVault.id
output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
