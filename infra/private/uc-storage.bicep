// ---------------------------------------------------------------------------
// Private Unity Catalog storage (ADLS Gen2) + Databricks Access Connector.
//
// This is the managed-storage backing for the Unity Catalog catalog used by the
// two managed MCP paths. Serverless SQL compute reaches it privately through a
// Network Connectivity Config (NCC) private endpoint (created out-of-band via the
// account API); management access from the injected VNet is served by front-end
// blob + dfs private endpoints. Public network access can be disabled once the
// NCC private path is live (see storagePublicNetworkAccess).
//
// The Databricks Access Connector (system-assigned managed identity) is granted
// Storage Blob Data Contributor and is later bound to a UC storage credential /
// external location so the catalog can manage data in this account.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Globally-unique ADLS Gen2 storage account name (3-24 lowercase alphanumeric).')
param storageAccountName string

@description('Filesystem (container) name for the Unity Catalog managed location.')
param filesystemName string = 'unity-catalog'

@description('Name of the Databricks Access Connector.')
param accessConnectorName string

@description('Resource ID of the private-endpoint subnet in the shared hub VNet.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.blob.core.windows.net private DNS zone.')
param blobDnsZoneId string

@description('Resource ID of the privatelink.dfs.core.windows.net private DNS zone.')
param dfsDnsZoneId string

@description('Public network access for the storage account. Set to Disabled once the NCC private path is validated.')
@allowed([
  'Enabled'
  'Disabled'
])
param storagePublicNetworkAccess string = 'Enabled'

@description('Tags applied to all resources.')
param tags object = {}

// Storage Blob Data Contributor
var blobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: storagePublicNetworkAccess
    networkAcls: {
      defaultAction: storagePublicNetworkAccess == 'Disabled' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource filesystem 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: filesystemName
  properties: {
    publicAccess: 'None'
  }
}

resource accessConnector 'Microsoft.Databricks/accessConnectors@2024-05-01' = {
  name: accessConnectorName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, accessConnector.id, blobDataContributorRoleId)
  scope: storage
  properties: {
    principalId: accessConnector.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Front-end private endpoints (management access from the injected VNet / DevBox).
resource blobPe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${storageAccountName}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${storageAccountName}-blob'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource blobDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: blobPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobDnsZoneId
        }
      }
    ]
  }
}

resource dfsPe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${storageAccountName}-dfs'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${storageAccountName}-dfs'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

resource dfsDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: dfsPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'dfs'
        properties: {
          privateDnsZoneId: dfsDnsZoneId
        }
      }
    ]
  }
}

output storageAccountId string = storage.id
output storageAccountName string = storage.name
output filesystemName string = filesystemName
output dfsEndpoint string = 'abfss://${filesystemName}@${storage.name}.dfs.core.windows.net/'
output accessConnectorId string = accessConnector.id
output accessConnectorPrincipalId string = accessConnector.identity.principalId
