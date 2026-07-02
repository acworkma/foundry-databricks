# Documentation

Reproducible, portal-based guides for building the **Data Quality Agent** — a Microsoft
Foundry agent connected to Azure Databricks. Every page is written so you can follow it in
**your own** subscription; values in angle brackets (e.g. `<subscription-id>`,
`<workspace-name>`, `<genie-space-id>`) are placeholders to replace with your own.

## Start here
- [Architecture](architecture.md) — the end-to-end design and request flow.
- [FoundryIQ positioning](foundryiq-positioning.md) — why managed MCP is the primary path and
  where FoundryIQ fits as a complement.

## Azure services (portal how-to + Bicep/CLI reference)
| Service | Page |
|---------|------|
| Azure Databricks workspace | [databricks-workspace.md](services/databricks-workspace.md) |
| Microsoft Foundry account & project | [foundry-account.md](services/foundry-account.md) |
| Foundry model deployment (gpt-4.1) | [foundry-model-deployment.md](services/foundry-model-deployment.md) |
| User-assigned managed identity | [managed-identity.md](services/managed-identity.md) |
| Key Vault | [key-vault.md](services/key-vault.md) |
| Storage account | [storage.md](services/storage.md) |
| Log Analytics workspace | [log-analytics.md](services/log-analytics.md) |

## Foundry ↔ Databricks integration patterns
| Pattern | Status | Page |
|---------|--------|------|
| A — Genie Space managed MCP | Built | [pattern-a-genie-mcp.md](integration/pattern-a-genie-mcp.md) |
| B — Unity Catalog Functions managed MCP | Built | [pattern-b-uc-functions-mcp.md](integration/pattern-b-uc-functions-mcp.md) |
| E — Custom MCP server (Container Apps) | Documented | [pattern-e-custom-mcp-server.md](integration/pattern-e-custom-mcp-server.md) |

## Related folders
- [`/infra`](../infra) — Bicep to deploy the environment.
- [`/databricks`](../databricks) — sample data + quality functions (runnable).
- [`/agent`](../agent) — agent instructions, skill definition, and sample prompts.

> **Preview features.** Databricks managed MCP servers and Genie-in-Foundry are Public
> Preview and are portal ("click-ops") steps — they are not ARM/Bicep-deployable today. Each
> integration page calls out the preview flags to enable.
