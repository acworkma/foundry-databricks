// ---------------------------------------------------------------------------
// Generic role assignment. Assigns a built-in role to a principal, scoped to
// one of the supported target resources. Declared as a module so the caller
// can pass a runtime principalId (module params are start-time inside here,
// which keeps the role-assignment name deterministic).
// ---------------------------------------------------------------------------
@description('Object ID of the principal receiving the role.')
param principalId string

@description('Built-in role definition GUID.')
param roleDefinitionId string

@description('Principal type.')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

@description('Target resource type for scoping.')
@allowed([
  'keyvault'
  'storage'
  'cognitiveservices'
])
param targetKind string

@description('Name of the existing target resource.')
param targetName string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (targetKind == 'keyvault') {
  name: targetName
}

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (targetKind == 'storage') {
  name: targetName
}

resource ai 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = if (targetKind == 'cognitiveservices') {
  name: targetName
}

resource kvAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (targetKind == 'keyvault') {
  name: guid(targetName, principalId, roleDefinitionId)
  scope: kv
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}

resource stAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (targetKind == 'storage') {
  name: guid(targetName, principalId, roleDefinitionId)
  scope: st
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}

resource aiAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (targetKind == 'cognitiveservices') {
  name: guid(targetName, principalId, roleDefinitionId)
  scope: ai
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
