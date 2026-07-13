// ---------------------------------------------------------------------------
// Custom MCP server (Pattern E / Option B) — Entra OAuth client app (Bicep).
//
// Approach A (user passthrough) needs an Entra application that Microsoft
// Foundry uses as the OAuth *client*. When a user invokes the custom MCP tool,
// Foundry's OAuth Identity Passthrough (Custom provider) uses this app to
// obtain an access token scoped to Azure Databricks
// (2ff814a6-.../user_impersonation) on the user's behalf, then forwards it as
// Authorization: Bearer to the MCP server, which relays it to the Databricks
// SQL Statement Execution API. Unity Catalog enforces the caller's own grants.
//
// This template declares the application + service principal + admin-consent
// grant for the Databricks delegated permission using the Microsoft Graph Bicep
// extension. Two things Graph/Bicep cannot emit declaratively are handled as
// documented post-steps (see docs/integration/custom-mcp-server.md):
//   1. The client secret (Bicep cannot output secrets) — generate with
//        az ad app credential reset --id <appId> --display-name foundry-oauth
//      and paste it into the Foundry OAuth connection.
//   2. The Foundry redirect URI (only known AFTER the Foundry connection is
//      created) — add it back with:
//        az ad app update --id <appId> --web-redirect-uris <foundry-redirect-uri>
//
// Deploy at tenant/subscription scope with the Microsoft Graph extension
// enabled (requires Application.ReadWrite.All + admin to consent).
// ---------------------------------------------------------------------------
extension microsoftGraphV1

@description('Display / unique name of the OAuth client app registration.')
param appName string = 'dq-mcp-server'

@description('App ID of the Azure Databricks first-party application (well-known constant).')
param databricksAppId string = '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d'

@description('ID of the Azure Databricks user_impersonation delegated permission (well-known constant).')
param databricksUserImpersonationId string = '739272be-e143-11e8-9f32-f2801f1b9fd1'

// Reference the Azure Databricks service principal already present in the tenant.
resource databricksSp 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: databricksAppId
}

// The OAuth client application registration.
resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appName
  displayName: appName
  signInAudience: 'AzureADMyOrg'
  requiredResourceAccess: [
    {
      resourceAppId: databricksAppId
      resourceAccess: [
        {
          id: databricksUserImpersonationId
          type: 'Scope'
        }
      ]
    }
  ]
}

// Its service principal (enterprise application).
resource sp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: app.appId
}

// Tenant-wide admin consent for the Databricks delegated permission, so users
// are not prompted to consent individually.
resource grant 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: sp.id
  resourceId: databricksSp.id
  consentType: 'AllPrincipals'
  scope: 'user_impersonation'
}

@description('Client (application) ID to configure in the Foundry OAuth connection.')
output clientId string = app.appId

@description('Service principal object ID.')
output servicePrincipalId string = sp.id
