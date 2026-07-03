// ===========================================================================
// Data Quality Agent — Microsoft Foundry + Azure Databricks
// Main deployment (resource-group scope).
//
// Provisions: Log Analytics, Storage, Key Vault, a user-assigned managed
// identity, an Azure Databricks workspace, and a Microsoft Foundry account +
// project + chat-model deployment, with least-privilege role assignments.
// ===========================================================================
targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short name used to derive resource names (3-12 lowercase alphanumeric).')
@minLength(3)
@maxLength(12)
param workloadName string = 'dqagent'

@description('Environment suffix (e.g. dev, test, demo).')
param environmentName string = 'demo'

@description('Chat model to deploy for the agent.')
param modelName string = 'gpt-4.1'

@description('Capacity (thousands of tokens per minute) for the model deployment.')
param modelCapacity int = 20

@description('Object ID of a user or group to grant data-plane access (Foundry User). Leave empty to skip.')
param developerPrincipalId string = ''

@description('Tags applied to every resource.')
param tags object = {
  workload: 'data-quality-agent'
  environment: environmentName
  solution: 'foundry-databricks'
}

// Deterministic, globally-unique-ish token for names that must be unique.
var token = uniqueString(subscription().id, resourceGroup().id, workloadName, environmentName)
var namePrefix = '${workloadName}-${environmentName}'

// Resource names computed at start (so role-assignment scopes/names resolve).
var storageName = take('st${workloadName}${token}', 24)
var keyVaultName = 'kv-${workloadName}-${take(token, 8)}'
var foundryAccountName = 'aif-${workloadName}-${take(token, 8)}'

// Role definition IDs (built-in).
var roleIds = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  cognitiveServicesUser: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  foundryUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}

// --------------------------- Observability ---------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    name: '${namePrefix}-log'
    tags: tags
  }
}

// ------------------------------ Storage ------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    name: storageName
    tags: tags
  }
}

// ------------------------------ Key Vault ----------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    name: keyVaultName
    tags: tags
  }
}

// ------------------------ Managed identity ---------------------------------
module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    location: location
    name: '${namePrefix}-mi'
    tags: tags
  }
}

// ------------------------------ Databricks ---------------------------------
module databricks 'modules/databricks.bicep' = {
  name: 'databricks'
  params: {
    location: location
    name: '${namePrefix}-dbw'
    tags: tags
  }
}

// ------------------------------- Foundry -----------------------------------
module foundry 'modules/foundry.bicep' = {
  name: 'foundry'
  params: {
    location: location
    accountName: foundryAccountName
    projectName: '${workloadName}-project'
    projectDisplayName: 'Data Quality Agent'
    modelName: modelName
    modelDeploymentName: modelName
    modelCapacity: modelCapacity
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Role assignments (least privilege).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Role assignments (least privilege). Implemented via the roleAssignment
// module so runtime principal IDs can be used deterministically.
// ---------------------------------------------------------------------------

// The managed identity can read secrets from Key Vault.
module miKeyVaultSecrets 'modules/roleAssignment.bicep' = {
  name: 'ra-mi-kv-secrets'
  params: {
    principalId: identity.outputs.principalId
    roleDefinitionId: roleIds.keyVaultSecretsUser
    targetKind: 'keyvault'
    targetName: keyVaultName
  }
  dependsOn: [keyVault]
}

// The managed identity can read/write blobs.
module miStorageBlob 'modules/roleAssignment.bicep' = {
  name: 'ra-mi-storage-blob'
  params: {
    principalId: identity.outputs.principalId
    roleDefinitionId: roleIds.storageBlobDataContributor
    targetKind: 'storage'
    targetName: storageName
  }
  dependsOn: [storage]
}

// The managed identity can call the Foundry account's models/inference.
module miCognitiveUser 'modules/roleAssignment.bicep' = {
  name: 'ra-mi-cognitive-user'
  params: {
    principalId: identity.outputs.principalId
    roleDefinitionId: roleIds.cognitiveServicesUser
    targetKind: 'cognitiveservices'
    targetName: foundryAccountName
  }
  dependsOn: [foundry]
}

// Optional: grant a human developer/group data-plane access to build agents.
module devFoundryUser 'modules/roleAssignment.bicep' = if (!empty(developerPrincipalId)) {
  name: 'ra-dev-foundry-user'
  params: {
    principalId: developerPrincipalId
    principalType: 'User'
    roleDefinitionId: roleIds.foundryUser
    targetKind: 'cognitiveservices'
    targetName: foundryAccountName
  }
  dependsOn: [foundry]
}

// ------------------------------- Outputs -----------------------------------
output resourceGroupName string = resourceGroup().name
output location string = location
output logAnalyticsName string = monitoring.outputs.name
output storageAccountName string = storage.outputs.name
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
output managedIdentityName string = identity.outputs.name
output managedIdentityClientId string = identity.outputs.clientId
output databricksWorkspaceName string = databricks.outputs.name
output databricksWorkspaceUrl string = databricks.outputs.workspaceUrl
output foundryAccountName string = foundry.outputs.accountName
output foundryProjectEndpoint string = foundry.outputs.projectEndpoint
output foundryModelDeploymentName string = foundry.outputs.modelDeploymentName
