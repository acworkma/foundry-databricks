// ---------------------------------------------------------------------------
// Databricks private DNS zones (centralized).
//
// Deploy to the CORE resource group that owns the shared hub VNet (the same
// place the other privatelink.* zones live), and link each zone to the shared
// VNet so private endpoints resolve to private IPs for VPN/spoke clients.
//
// These two zones are the only DNS zones Databricks needs that are NOT already
// present in the core resource group:
//   - privatelink.azuredatabricks.net    workspace front-end (UI/API) Private Link
//   - privatelink.dfs.core.windows.net   Unity Catalog / DBFS ADLS Gen2 storage
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Resource ID of the shared hub VNet to link the zones to (your shared hub VNet in the core RG).')
param sharedVnetId string

@description('Tags applied to the DNS zones and links.')
param tags object = {}

var zoneNames = [
  'privatelink.azuredatabricks.net'
  'privatelink.dfs.core.windows.net'
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in zoneNames: {
  name: zone
  location: 'global'
  tags: tags
  properties: {}
}]

resource dnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in zoneNames: {
  parent: dnsZones[i]
  name: '${split(sharedVnetId, '/')[8]}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: sharedVnetId
    }
  }
}]

output zoneIds array = [for (zone, i) in zoneNames: dnsZones[i].id]
output zoneNames array = zoneNames
