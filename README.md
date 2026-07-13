# Data Quality Agent — Microsoft Foundry + Azure Databricks

A reference solution that connects a **Microsoft Foundry** agent to **Azure Databricks** (Unity Catalog)
to run a standardized **data quality assessment** on any table or view across six dimensions —
**accuracy, completeness, consistency, timeliness, validity, and uniqueness** — and return a scored
report with severity classification and recommended remediation.

This repo is a **first-read, reproducible guide**: everything here is designed so you can stand the same
solution up in **your own Azure subscription** using the included Bicep and step-by-step portal docs.

---

## What you get

- **Infrastructure as Code (Bicep)** that provisions the full environment: an Azure Databricks workspace,
  a Microsoft Foundry account + project + chat-model deployment, a user-assigned managed identity,
  Key Vault, Storage, Log Analytics, and least-privilege role assignments.
- **A defect-seeded sample dataset** in Unity Catalog so the agent has something real to assess — with
  intentional quality issues across all six dimensions, plus a "healthy" and a "problem" table so a
  single run shows the full severity range.
- **Databricks data-quality logic** exposed as governed Unity Catalog functions that return a structured,
  scored JSON assessment.
- **Two working integration patterns** for connecting Foundry to Databricks, plus a third documented as a
  future option.
- **Per-service documentation** with portal how-to steps and the equivalent Bicep/CLI.

## Integration patterns

| Pattern | What it is | In this repo |
| --- | --- | --- |
| **Genie Space (managed MCP)** | Natural-language Q&A over your data via a Databricks Genie Space, added to Foundry as an MCP tool. | **Built** |
| **Unity Catalog Functions (managed MCP)** | Data-quality checks and scoring implemented as governed UC functions, called by the agent as tools. | **Built** |
| **Custom MCP server** | Your own Python MCP server (wrapping the Databricks SQL Statement Execution API + a scoring engine) on **dedicated compute**, hosted on a private Azure Container App and registered in Foundry via OAuth passthrough. | **Built** |

> See [`docs/integration/`](docs/integration/) for a page on each pattern, and
> [`docs/foundryiq-positioning.md`](docs/foundryiq-positioning.md) for where Foundry IQ fits.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for the full diagram and data flow.

```
User / Data Engineer
        │  "Assess quality for catalog.schema.table"
        ▼
Microsoft Foundry Agent (gpt-4.1)
        │  selects a tool (Genie MCP  |  UC Functions MCP)
        ▼
Azure Databricks — Unity Catalog
        │  metadata, profiling, 6-dimension checks + scoring
        ▼
Scored assessment  →  severity + findings + recommendations
```

## Repository layout

```
infra/            Bicep templates and parameters (deploy the whole environment)
databricks/       Unity Catalog sample data (seed scripts) and data-quality functions
agent/            Foundry agent instructions, tool config, and sample prompts
docs/
  services/       One page per Azure service, with portal how-to + Bicep/CLI
  integration/    The integration patterns (Genie MCP, UC Functions MCP, custom MCP)
```

## Quickstart

1. **Prerequisites** — an Azure subscription, the Azure CLI, and permission to create resources and role
   assignments. See [`docs/services/`](docs/services/) for details.
2. **Deploy the infrastructure** — follow [`infra/README.md`](infra/README.md).
3. **Seed the sample data and create the quality functions** — follow [`databricks/README.md`](databricks/README.md).
4. **Wire up the agent** — follow the integration pattern of your choice in
   [`docs/integration/`](docs/integration/).

## Important notes

- Several capabilities used here (Azure Databricks **managed MCP servers**, **Genie in Microsoft Foundry**)
  are in **Public Preview**. Enable the relevant workspace previews before you begin.
- All sample data is **synthetic and contains no PII/PHI**. Keep real assessments free of sensitive sample
  values per your organization's governance policy.
