// ---------------------------------------------------------------------------
// Custom MCP server (Pattern E / Option B) — private Azure Container App.
//
// Hosts the "assess any table" MCP server on dedicated compute, fully private:
//   - Deployed into an EXISTING internal (VNet-injected) Container Apps
//     environment, so it has no public IP. Ingress is marked external so the
//     environment's envoy routes it, but because the environment itself is
//     internal the app is reachable only from inside the VNet (and its callers
//     resolve it through the environment's privatelink DNS zone).
//   - Image is pulled from the EXISTING private Azure Container Registry
//     (publicNetworkAccess=Disabled) using a user-assigned managed identity
//     that holds AcrPull. No admin user, no registry password.
//   - The server forwards the caller's Databricks-scoped bearer token to the
//     SQL Statement Execution API of a dedicated (Pro/classic) SQL warehouse,
//     so Unity Catalog enforces each user's own grants (approach A passthrough).
//
// This module deploys ONLY the app + its pull identity + the AcrPull role.
// The Container Apps environment, the ACR, the dedicated warehouse, and the
// Entra OAuth app registration are pre-existing / created elsewhere and passed
// in as parameters or resource ids.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Azure region for the container app.')
param location string = resourceGroup().location

@description('Name of the container app.')
param name string = 'dq-mcp-server'

@description('Resource ID of the EXISTING internal Container Apps managed environment to deploy into.')
param managedEnvironmentId string

@description('Login server of the EXISTING private Azure Container Registry, e.g. <registry>.azurecr.io')
param acrLoginServer string

@description('Resource ID of the EXISTING private Azure Container Registry (for the AcrPull role assignment).')
param acrResourceId string

@description('Fully-qualified container image reference, e.g. <registry>.azurecr.io/dq-mcp-server:v2')
param image string

@description('Databricks workspace host (no scheme), e.g. adb-<id>.<n>.azuredatabricks.net')
param databricksHost string

@description('ID of the dedicated (Pro/classic) SQL warehouse the server queries.')
param databricksWarehouseId string

@description('Target port the MCP server listens on.')
param targetPort int = 8000

@description('Minimum replica count. Use 0 for scale-to-zero (cold start on first call).')
param minReplicas int = 1

@description('Maximum replica count.')
param maxReplicas int = 3

// User-assigned managed identity used only to pull from the private ACR.
resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${name}'
  location: location
}

// AcrPull on the private registry for the pull identity.
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: last(split(acrResourceId, '/'))
}
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrResourceId, pullIdentity.id, acrPullRoleId)
  scope: acr
  properties: {
    principalId: pullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${pullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      // external ingress on an INTERNAL environment = routable but private-only.
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: pullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'DATABRICKS_HOST'
              value: databricksHost
            }
            {
              name: 'DATABRICKS_WAREHOUSE_ID'
              value: databricksWarehouseId
            }
            {
              // DNS-rebinding host allowlist for the private ingress FQDN
              // (FastMCP rejects non-localhost Host headers by default).
              name: 'MCP_ALLOWED_HOSTS'
              value: '${name}.${reference(managedEnvironmentId, '2024-03-01').defaultDomain}'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
  dependsOn: [
    acrPull
  ]
}

@description('Private ingress FQDN of the MCP server (append /mcp for the endpoint).')
output fqdn string = app.properties.configuration.ingress.fqdn

@description('Principal ID of the pull identity.')
output pullIdentityPrincipalId string = pullIdentity.properties.principalId
