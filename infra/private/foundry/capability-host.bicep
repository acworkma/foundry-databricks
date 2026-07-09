// Project capability host (Agents) wired to the shared dependency connections.
targetScope = 'resourceGroup'

param accountName string
param projectName string
param projectCapHost string
param cosmosDbConnection string
param storageConnection string
param aiSearchConnection string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: projectCapHost
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    vectorStoreConnections: [
      aiSearchConnection
    ]
    storageConnections: [
      storageConnection
    ]
    threadStorageConnections: [
      cosmosDbConnection
    ]
  }
}

output projectCapHostName string = projectCapabilityHost.name
