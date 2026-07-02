# SKILL: Data Quality Assessment

A portable description of the **data quality assessment skill** the agent performs. It is
written so it can be pasted into a Foundry agent's instructions, stored as a reusable
"skill" document, or used as a knowledge-source file. It is intentionally
tool-agnostic: the same skill works whether the agent reaches Databricks through the
**Genie Space** (Pattern A) or the **Unity Catalog Functions** MCP server (Pattern B).

## Purpose

Given a Unity Catalog table or view, produce a **standardized data quality assessment**
across six dimensions, a composite score, a severity rating, and concrete recommendations.

## The six dimensions

| Dimension | Question it answers |
|-----------|---------------------|
| Completeness | Are required fields populated? |
| Uniqueness | Are keys free of duplicates? |
| Validity | Do values match expected formats and domains? |
| Timeliness | Is the data fresh enough for its refresh target? |
| Consistency | Do values reconcile within and across tables? |
| Accuracy | Do values obey known business rules? |

## Scoring model

Each dimension is scored in `[0, 1]` as `1 - (issues / checks)`. The composite score is the
mean of the assessed dimensions (dimensions with no defined rule are reported as
*Not Assessed* and excluded from the mean).

| Composite score | Severity | Recommended action |
|-----------------|----------|--------------------|
| 0.95 – 1.00 | **Healthy** | Publish as low-risk; monitor the trend. |
| 0.85 – 0.94 | **Needs Attention** | Review findings; assign remediation if business impact exists. |
| 0.70 – 0.84 | **High Risk** | Create a work item; validate the upstream pipeline/source. |
| < 0.70 | **Critical** | Escalate; consider suppressing downstream use until resolved. |

## How the agent should work

1. **Identify the target** table/view from the user's request. If ambiguous, ask.
2. **Gather evidence** using the available tool:
   - *Pattern B (preferred for the demo tables):* call the governed
     `assess_customers` / `assess_orders` / `assess_products` functions and the scalar
     scorers (`dq_ratio_score`, `dq_freshness_score`, `dq_composite`, `dq_severity`,
     `dq_recommend`).
   - *Pattern A (arbitrary tables):* ask the Genie Space natural-language questions that
     map to each dimension (see `agent/sample-prompts.md`).
3. **Compute** the composite score and severity using the scoring model above.
4. **Report** using the output contract below. Always cite the concrete numbers behind each
   score (e.g. "2 null emails out of 11 rows").
5. **Never invent numbers.** If a dimension has no rule/evidence, mark it *Not Assessed*.

## Output contract

```json
{
  "table": "<catalog>.<schema>.<table>",
  "assessed_at": "<iso-8601>",
  "records_checked": 0,
  "dimensions": [
    {"dimension": "completeness", "score": 0.0, "issues_found": 0, "severity": "", "finding": ""}
  ],
  "composite_score": 0.0,
  "severity": "Healthy | Needs Attention | High Risk | Critical",
  "recommendations": ["..."]
}
```

The agent may also render a short human-readable summary table, but the JSON is the source
of truth so results can be logged and trended.

## Guardrails

- Read-only. The skill never mutates source data.
- Sample data is synthetic and non-PII; keep any real deployment scoped to non-sensitive
  data or apply Unity Catalog governance before pointing the agent at production tables.
