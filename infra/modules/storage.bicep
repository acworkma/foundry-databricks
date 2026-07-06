// ---------------------------------------------------------------------------
// Storage account — general-purpose v2, secured for solution artifacts.
// ---------------------------------------------------------------------------
@description('Azure region for the storage account.')
param location string

@description('Globally unique storage account name (3-24 lowercase alphanumeric).')
param name string

@description('Tags applied to the resource.')
param tags object = {}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

output id string = storage.id
output name string = storage.name
