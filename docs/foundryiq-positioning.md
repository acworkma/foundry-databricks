# FoundryIQ — positioning for this solution

A common question when building a Foundry agent over enterprise data is: *"Should we use
FoundryIQ for this?"* This page explains what FoundryIQ is and why the Data Quality Agent
uses **managed MCP over Databricks** as its primary path rather than FoundryIQ.

## What FoundryIQ is
FoundryIQ is Microsoft Foundry's **knowledge / retrieval layer**. It lets you build and query
a knowledge base — typically **unstructured or semi-structured content** (documents, PDFs,
web pages, wikis) — with retrieval-augmented generation (RAG) built on **Azure AI Search**
(vector + hybrid retrieval). It's about giving an agent grounded *knowledge* to read.

## What this solution needs
The Data Quality Agent must run **deterministic computations over live, structured tables**
in Unity Catalog: count nulls, detect duplicate keys, reconcile totals across tables, check
freshness, and produce reproducible scores. That is a **structured-data / query** problem,
not a document-retrieval problem.

## Why managed MCP is the primary path
| Requirement | Managed MCP over Databricks (A/B) | FoundryIQ (RAG) |
|-------------|-----------------------------------|-----------------|
| Live counts/aggregations over tables | ✅ SQL executes on current data | ❌ retrieves indexed text, doesn't compute |
| Deterministic, reproducible scores | ✅ (Pattern B functions) | ❌ answers vary with retrieval/model |
| Cross-table reconciliation (consistency) | ✅ joins in SQL | ❌ |
| Data freshness (timeliness) | ✅ reads max timestamps now | ❌ index can be stale |
| Unity Catalog governance / row-level security | ✅ enforced at query time | ⚠️ depends on indexing pipeline |

For structured quality assessment, you want the agent to **query the source of truth**, which
is exactly what the Genie (A) and UC Functions (B) managed MCP servers provide.

## Where FoundryIQ *does* fit (complementary)
FoundryIQ is a strong **add-on**, not the core engine, for use cases like:
- **Data quality playbooks / standards** — index your DQ policy docs, remediation runbooks,
  and data contracts so the agent can explain *how* to fix an issue or *why* a rule exists.
- **Data dictionaries / catalog descriptions** — index business glossaries so the agent can
  translate business terms to the right tables/columns before it queries.
- **Onboarding & FAQs** — index internal docs so the agent can answer "how do I request
  access to this catalog?"-style questions.

A mature deployment could combine both: **MCP (A/B)** to measure quality, **FoundryIQ** to
retrieve the policy/remediation knowledge that turns a finding into an action.

## Recommendation
- **Primary:** Genie managed MCP (A) + Unity Catalog Functions managed MCP (B) for the actual
  assessment. This is what the repo builds.
- **Optional enhancement:** add FoundryIQ (Azure AI Search) as a knowledge source for DQ
  standards, the data dictionary, and remediation guidance — not for computing scores.

## References
- [Microsoft Foundry documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Azure AI Search](https://learn.microsoft.com/azure/search/)
- [Retrieval-augmented generation in Azure AI Search](https://learn.microsoft.com/azure/search/retrieval-augmented-generation-overview)
