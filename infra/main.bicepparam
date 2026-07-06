using 'main.bicep'

// Short name used to derive resource names (3-12 lowercase alphanumeric).
param workloadName = 'dqagent'

// Environment suffix (e.g. dev, test, demo).
param environmentName = 'demo'

// Chat model deployed for the agent.
param modelName = 'gpt-4.1'

// Capacity in thousands of tokens per minute for the model deployment.
param modelCapacity = 50

// Optional: object ID of a user/group to grant "Foundry User" on the
// Foundry account so they can build agents in the portal. Leave '' to skip.
// Find yours with: az ad signed-in-user show --query id -o tsv
param developerPrincipalId = ''
