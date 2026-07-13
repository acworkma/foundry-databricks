// ---------------------------------------------------------------------------
// Databricks VNet-injection subnets (added to the existing shared hub VNet).
//
// Azure Databricks requires VNet injection in order to disable public network
// access (a non-injected workspace cannot set publicNetworkAccess=Disabled).
// Two delegated subnets are required — a "host" (public) and "container"
// (private) subnet — both delegated to Microsoft.Databricks/workspaces and
// associated with an NSG. Databricks manages the required NSG rules itself.
//
// Deployed into the CORE resource group that owns the shared VNet.
// Subnet writes on a single VNet must be serialized, so the container subnet
// depends on the host subnet.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Name of the shared hub VNet to add the subnets to.')
param sharedVnetName string

@description('Azure region (for the NSG).')
param location string

@description('Host (public) subnet name.')
param hostSubnetName string = 'snet-databricks-host'

@description('Host (public) subnet address prefix.')
param hostSubnetPrefix string = '10.10.0.192/26'

@description('Container (private) subnet name.')
param containerSubnetName string = 'snet-databricks-container'

@description('Container (private) subnet address prefix.')
param containerSubnetPrefix string = '10.10.1.64/26'

@description('NSG name for the Databricks subnets.')
param nsgName string = 'nsg-databricks'

@description('Tags applied to the NSG.')
param tags object = {}

resource sharedVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: sharedVnetName
}

// Databricks populates the required inbound/outbound rules on this NSG itself.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

var databricksDelegation = [
  {
    name: 'databricks-del'
    properties: {
      serviceName: 'Microsoft.Databricks/workspaces'
    }
  }
]

var databricksServiceEndpoints = [
  {
    service: 'Microsoft.Storage'
  }
  {
    service: 'Microsoft.KeyVault'
  }
]

resource hostSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: sharedVnet
  name: hostSubnetName
  properties: {
    addressPrefix: hostSubnetPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
    delegations: databricksDelegation
    serviceEndpoints: databricksServiceEndpoints
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

resource containerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: sharedVnet
  name: containerSubnetName
  properties: {
    addressPrefix: containerSubnetPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
    delegations: databricksDelegation
    serviceEndpoints: databricksServiceEndpoints
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  // Serialize subnet writes on the shared VNet.
  dependsOn: [
    hostSubnet
  ]
}

output nsgId string = nsg.id
output hostSubnetName string = hostSubnet.name
output containerSubnetName string = containerSubnet.name
output hostSubnetId string = hostSubnet.id
output containerSubnetId string = containerSubnet.id
