// Orchestrator: add a private Foundry project (Agents) onto an EXISTING private
// Foundry account, reusing that account's already-deployed Search / Storage / Cosmos
// dependencies. Mirrors the AI-Lab bicep/foundry module ordering so role-assignment
// names resolve at each nested-deployment boundary (they take the project identity
// and workspace GUID as params rather than referencing runtime resource properties).
targetScope = 'resourceGroup'

@description('Existing private Foundry (AIServices) account to add the project to.')
param accountName string

@description('Location for the new project (match the account).')
param location string = resourceGroup().location

@description('Name of the new Data Quality Agent project.')
param projectName string

param projectDescription string = 'Data Quality Agent project (private).'
param displayName string = 'Data Quality Agent'

@description('Capability host name for the project.')
param projectCapHost string = 'projectcaphost'

@description('Existing shared dependencies on the account.')
param aiSearchName string
param cosmosDbName string
param storageName string

module project 'project.bicep' = {
  name: 'project'
  params: {
    accountName: accountName
    location: location
    projectName: projectName
    projectDescription: projectDescription
    displayName: displayName
    aiSearchName: aiSearchName
    cosmosDbName: cosmosDbName
    storageName: storageName
  }
}

module accountRbac 'rbac-account.bicep' = {
  name: 'account-rbac'
  params: {
    projectPrincipalId: project.outputs.projectPrincipalId
    aiSearchName: aiSearchName
    cosmosDbName: cosmosDbName
    storageName: storageName
  }
}

module capabilityHost 'capability-host.bicep' = {
  name: 'capability-host'
  params: {
    accountName: accountName
    projectName: project.outputs.projectName
    projectCapHost: projectCapHost
    cosmosDbConnection: project.outputs.cosmosDbConnection
    storageConnection: project.outputs.storageConnection
    aiSearchConnection: project.outputs.aiSearchConnection
  }
  dependsOn: [
    accountRbac
  ]
}

module formatWorkspaceId 'format-workspace-id.bicep' = {
  name: 'format-workspace-id'
  params: {
    projectWorkspaceId: project.outputs.projectWorkspaceId
  }
}

module containerRbac 'rbac-container.bicep' = {
  name: 'container-rbac'
  params: {
    storageName: storageName
    cosmosAccountName: cosmosDbName
    projectPrincipalId: project.outputs.projectPrincipalId
    projectWorkspaceGuid: formatWorkspaceId.outputs.projectWorkspaceIdGuid
  }
  dependsOn: [
    capabilityHost
  ]
}

output projectName string = project.outputs.projectName
output projectPrincipalId string = project.outputs.projectPrincipalId
output projectWorkspaceIdGuid string = formatWorkspaceId.outputs.projectWorkspaceIdGuid
