// ---------------------------------------------------------------------------
// Microsoft Foundry — an AI Services account with project management enabled,
// a default project, and a chat-model deployment for the agent to use.
// ---------------------------------------------------------------------------
@description('Azure region for the Foundry account.')
param location string

@description('Name of the Foundry (AI Services) account. Must be globally unique; becomes the custom subdomain.')
param accountName string

@description('Name of the default Foundry project.')
param projectName string

@description('Display name for the project.')
param projectDisplayName string = 'Data Quality Agent'

@description('Tags applied to the resources.')
param tags object = {}

@description('Chat model to deploy for the agent.')
param modelName string = 'gpt-4.1'

@description('Model version. Leave empty to use the account default for the model.')
param modelVersion string = ''

@description('Deployment (SKU) name for the model deployment.')
param modelDeploymentName string = 'gpt-4.1'

@description('SKU for the model deployment.')
param modelSkuName string = 'GlobalStandard'

@description('Capacity (tokens-per-minute in thousands) for the model deployment.')
param modelCapacity int = 50

// AI Services account with Foundry project management enabled.
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Enables Foundry projects (the "hub-free" Foundry account experience).
    allowProjectManagement: true
    // The account name is used as the custom subdomain, which the Foundry
    // and agent endpoints require.
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectDisplayName
    description: 'Agent project for the Foundry + Databricks data quality assessment solution.'
  }
}

// Chat-model deployment used by the agent. Deployed on the account (models are
// account-scoped and shared by the account's projects).
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: empty(modelVersion) ? null : modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

output accountId string = account.id
output accountName string = account.name
output accountEndpoint string = account.properties.endpoint
output projectName string = project.name
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output modelDeploymentName string = modelDeployment.name
