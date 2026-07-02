// ---------------------------------------------------------------------------
// Azure Databricks workspace (Premium SKU — required for Unity Catalog,
// serverless SQL warehouses, and managed MCP servers).
// ---------------------------------------------------------------------------
@description('Azure region for the workspace.')
param location string

@description('Name of the Databricks workspace.')
param name string

@description('Tags applied to the resource.')
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
  }
}

output id string = databricks.id
output name string = databricks.name
output workspaceUrl string = databricks.properties.workspaceUrl
