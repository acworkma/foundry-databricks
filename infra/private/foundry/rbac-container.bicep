// Container-scoped runtime RBAC created AFTER the project capability host provisions
// its agent containers. Blob Data Owner is conditioned to this project's workspace
// containers; the Cosmos SQL role grants data-plane access to enterprise_memory.
// Names include the project principal / workspace GUID so they never collide with a
// sibling project on the shared resources.
targetScope = 'resourceGroup'

param storageName string
param cosmosAccountName string
param projectPrincipalId string
param projectWorkspaceGuid string

var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosAccountName
}

var blobOwnerCondition = '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'})  AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${projectWorkspaceGuid}\' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase \'*-azureml-agent\'))'

resource storageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(projectPrincipalId, storageBlobDataOwnerRoleId, storage.id)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalType: 'ServicePrincipal'
    conditionVersion: '2.0'
    condition: blobOwnerCondition
  }
}

var cosmosDataContributorRoleDefId = resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosAccountName, '00000000-0000-0000-0000-000000000002')

resource cosmosContainerRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosAccount
  name: guid(projectWorkspaceGuid, cosmosAccountName, cosmosDataContributorRoleDefId, projectPrincipalId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorRoleDefId
    scope: '${cosmosAccount.id}/dbs/enterprise_memory'
  }
}
