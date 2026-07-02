# Microsoft Foundry account & project

## What it is
The **Microsoft Foundry** account is an **Azure AI Services** resource with project
management enabled — the "hub-free" Foundry experience. It hosts one or more **projects**,
which contain your agents, tools, and model deployments. This solution creates one account
and one project for the Data Quality Agent.

## Prerequisites
- Permission to create Cognitive Services / AI Services resources.
- The `Microsoft.CognitiveServices` provider registered.
- A globally unique account name (it becomes the custom subdomain).

## Create it in the portal
You can create everything from the **Foundry portal**:
1. Go to the [Foundry portal](https://ai.azure.com).
2. **Create project** → choose **Create new resource** when prompted.
3. Set:
   - **Subscription / Resource group:** `<subscription-id>` / `<resource-group>`.
   - **Foundry resource (account) name:** `<foundry-account>`.
   - **Project name:** `<project-name>`.
   - **Region:** `<region>` (e.g. East US 2).
4. **Create.** This provisions the AI Services account, the project, and the endpoints.

The project endpoint has the form:
```
https://<foundry-account>.services.ai.azure.com/api/projects/<project-name>
```

## Roles
- **Azure AI Developer** on the project to build agents and add tools.
- **Cognitive Services User** to call the deployed models.

## Bicep / CLI reference
Deployed by [`infra/modules/foundry.bicep`](../../infra/modules/foundry.bicep):
```bicep
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: '<foundry-account>'
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true      // enables Foundry projects
    customSubDomainName: '<foundry-account>'
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: '<project-name>'
  properties: { displayName: 'Data Quality Agent' }
}
```

## Verify
- The account shows **Kind = AIServices** and a **custom subdomain**.
- The project appears in the Foundry portal and its **endpoint** resolves.
- You can open **Agents** in the project (ready for the model deployment and tools).

## Next
- Deploy the chat model: [Foundry model deployment](foundry-model-deployment.md).
- Build the agent: [`/agent`](../../agent).
