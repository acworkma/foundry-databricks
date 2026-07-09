// Account-scoped RBAC for the project identity on the shared Foundry dependencies.
// Names include projectPrincipalId (a module param) so they never collide with a
// sibling project's assignments on the same shared resources.
targetScope = 'resourceGroup'

param projectPrincipalId string
param aiSearchName string
param cosmosDbName string
param storageName string

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var cosmosDbOperatorRoleId = '230815da-be43-4aae-9cb4-875f7bd000aa'

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: aiSearchName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosDbName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(projectPrincipalId, storageBlobDataContributorRoleId, storageAccount.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource searchIndexContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(projectPrincipalId, searchIndexDataContributorRoleId, searchService.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(projectPrincipalId, searchServiceContributorRoleId, searchService.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource cosmosDbOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosDbAccount
  name: guid(projectPrincipalId, cosmosDbOperatorRoleId, cosmosDbAccount.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cosmosDbOperatorRoleId)
    principalType: 'ServicePrincipal'
  }
}
