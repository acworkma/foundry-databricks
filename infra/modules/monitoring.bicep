// ---------------------------------------------------------------------------
// Log Analytics workspace — central logging/observability for the solution.
// ---------------------------------------------------------------------------
@description('Azure region for the workspace.')
param location string

@description('Name of the Log Analytics workspace.')
param name string

@description('Tags applied to the resource.')
param tags object = {}

@description('Retention in days for ingested logs.')
param retentionInDays int = 30

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output id string = logAnalytics.id
output name string = logAnalytics.name
output customerId string = logAnalytics.properties.customerId
