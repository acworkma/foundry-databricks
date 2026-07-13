"""The six-dimension data-quality scoring model.

This is a faithful Python port of the Unity Catalog scalar functions in
``databricks/sql/03_quality_functions.sql`` (dq_ratio_score, dq_freshness_score,
dq_composite, dq_severity, dq_recommend). Keeping the math here — and pulling only
raw counts from SQL — guarantees the custom MCP server produces scores identical to
the UC Functions path for the same table.

Pure standard library so it can be unit-tested without any dependencies.
"""
from __future__ import annotations

from typing import Optional, Sequence

# Severity bands (composite score -> label). Mirrors dq_severity().
HEALTHY = "Healthy"
NEEDS_ATTENTION = "Needs Attention"
HIGH_RISK = "High Risk"
CRITICAL = "Critical"
NOT_ASSESSED = "Not Assessed"


def ratio_score(issues: Optional[int], checks: Optional[int]) -> float:
    """Score = 1 - (issues / checks), clamped to [0, 1]. Empty checks => perfect."""
    if checks is None or checks <= 0:
        return 1.0
    return max(0.0, 1.0 - (issues or 0) * 1.0 / checks)


def freshness_score(age_days: Optional[int], target_days: int) -> Optional[float]:
    """Full marks within target_days, decays linearly over a year."""
    if age_days is None:
        return None
    if age_days <= target_days:
        return 1.0
    return max(0.0, 1.0 - (age_days - target_days) / 365.0)


def composite(scores: Sequence[Optional[float]]) -> Optional[float]:
    """Mean of the assessed dimension scores, ignoring None (Not Assessed)."""
    assessed = [s for s in scores if s is not None]
    if not assessed:
        return None
    return sum(assessed) / len(assessed)


def severity(score: Optional[float]) -> str:
    """Map a 0..1 score to a severity band. Mirrors dq_severity()."""
    if score is None:
        return NOT_ASSESSED
    if score >= 0.95:
        return HEALTHY
    if score >= 0.85:
        return NEEDS_ATTENTION
    if score >= 0.70:
        return HIGH_RISK
    return CRITICAL


def recommend(score: Optional[float]) -> str:
    """Suggested action for a score, aligned to the severity bands. Mirrors dq_recommend()."""
    if score is None:
        return "Define a rule so this dimension can be assessed."
    if score >= 0.95:
        return "Publish as low-risk; monitor trend."
    if score >= 0.85:
        return "Review findings; assign remediation if business impact exists."
    if score >= 0.70:
        return "Create a work item; validate the upstream pipeline/source."
    return "Escalate; consider suppressing downstream use until resolved."


def dimension(name: str, records_checked: Optional[int], issues_found: Optional[int],
              score: Optional[float], finding: str) -> dict:
    """Build one dimension entry for the output contract."""
    return {
        "dimension": name,
        "records_checked": records_checked,
        "issues_found": issues_found,
        "score": None if score is None else round(score, 4),
        "severity": severity(score),
        "finding": finding,
    }
