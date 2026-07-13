// ---------------------------------------------------------------------------
// Private Azure Databricks workspace (serverless model — Option A).
//
// Premium SKU (required for Unity Catalog, serverless SQL warehouses, and
// managed MCP servers). Public network access is DISABLED; the workspace is
// reachable only through front-end Private Link:
//   - databricks_ui_api        web UI + REST API (incl. the /api/2.0/mcp/* endpoints)
//   - browser_authentication   Entra ID SSO sign-in flow
// Both private endpoints resolve via the privatelink.azuredatabricks.net zone.
//
// The workspace IS VNet-injected: Azure Databricks only permits
// publicNetworkAccess=Disabled on an injected workspace. Two delegated subnets
// (host/container) are required even though serverless is the primary compute.
// Secure Cluster Connectivity (enableNoPublicIp) is on. Serverless egress to
// storage is locked down separately by a Network Connectivity Config (NCC).
// requiredNsgRules = NoAzureDatabricksRules (required when public access is
// disabled); back-end connectivity is served by the databricks_ui_api PE.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Azure region for the workspace.')
param location string

@description('Name of the Databricks workspace.')
param name string

@description('Resource ID of the shared hub VNet to inject the workspace into.')
param customVirtualNetworkId string

@description('Host (public) subnet name for VNet injection.')
param customPublicSubnetName string

@description('Container (private) subnet name for VNet injection.')
param customPrivateSubnetName string

@description('Resource ID of the private-endpoint subnet in the shared hub VNet.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.azuredatabricks.net private DNS zone (in the core RG).')
param databricksDnsZoneId string

@description('Also create the browser_authentication private endpoint (Entra SSO front-end PL).')
param createBrowserAuthEndpoint bool = true

@description('Tags applied to all resources.')
param tags object = {}

@description('Resource ID of the managed resource group Databricks creates for its data-plane resources.')
param managedResourceGroupId string = subscriptionResourceId('Microsoft.Resources/resourceGroups', '${name}-managed-rg')

resource databricks 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'premium'
  }
  properties: {
    managedResourceGroupId: managedResourceGroupId
    publicNetworkAccess: 'Disabled'
    // Public access is disabled, so the classic compute plane reaches the
    // control plane through the databricks_ui_api private endpoint (same VNet)
    // rather than the public Azure Databricks NSG rules.
    requiredNsgRules: 'NoAzureDatabricksRules'
    parameters: {
      customVirtualNetworkId: {
        value: customVirtualNetworkId
      }
      customPublicSubnetName: {
        value: customPublicSubnetName
      }
      customPrivateSubnetName: {
        value: customPrivateSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
  }
}

// Front-end Private Link: UI + REST API (this is the endpoint Foundry managed MCP calls).
resource uiApiPe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${name}-ui-api'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${name}-ui-api'
        properties: {
          privateLinkServiceId: databricks.id
          groupIds: [
            'databricks_ui_api'
          ]
        }
      }
    ]
  }
}

resource uiApiDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: uiApiPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azuredatabricks'
        properties: {
          privateDnsZoneId: databricksDnsZoneId
        }
      }
    ]
  }
}

// Front-end Private Link: Entra ID browser SSO sign-in.
resource browserAuthPe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (createBrowserAuthEndpoint) {
  name: 'pe-${name}-browser-auth'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${name}-browser-auth'
        properties: {
          privateLinkServiceId: databricks.id
          groupIds: [
            'browser_authentication'
          ]
        }
      }
    ]
  }
}

resource browserAuthDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (createBrowserAuthEndpoint) {
  parent: browserAuthPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azuredatabricks'
        properties: {
          privateDnsZoneId: databricksDnsZoneId
        }
      }
    ]
  }
}

output id string = databricks.id
output name string = databricks.name
output workspaceUrl string = databricks.properties.workspaceUrl
output workspaceResourceId string = databricks.id
