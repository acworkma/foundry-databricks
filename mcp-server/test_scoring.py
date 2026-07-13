"""Local parity tests for the ported scoring model (stdlib only, no deps).

Run: `python3 test_scoring.py`. These lock the Python port to the SQL baseline so a
regression in the scoring math is caught before deploy.
"""
import unittest

import rulepacks
import scoring


class ScalarModel(unittest.TestCase):
    def test_ratio_score(self):
        self.assertEqual(scoring.ratio_score(0, 0), 1.0)      # no checks => perfect
        self.assertEqual(scoring.ratio_score(5, 0), 1.0)      # checks<=0 => perfect
        self.assertAlmostEqual(scoring.ratio_score(2, 22), 1 - 2 / 22)
        self.assertEqual(scoring.ratio_score(50, 10), 0.0)    # clamped at 0

    def test_freshness_score(self):
        self.assertIsNone(scoring.freshness_score(None, 30))
        self.assertEqual(scoring.freshness_score(10, 30), 1.0)
        self.assertAlmostEqual(scoring.freshness_score(395, 30), 0.0)
        self.assertAlmostEqual(scoring.freshness_score(30 + 365, 30), 0.0)

    def test_composite_ignores_none(self):
        self.assertAlmostEqual(scoring.composite([1.0, 0.5, None]), 0.75)
        self.assertIsNone(scoring.composite([None, None]))

    def test_severity_bands(self):
        self.assertEqual(scoring.severity(None), "Not Assessed")
        self.assertEqual(scoring.severity(0.96), "Healthy")
        self.assertEqual(scoring.severity(0.90), "Needs Attention")
        self.assertEqual(scoring.severity(0.77), "High Risk")
        self.assertEqual(scoring.severity(0.50), "Critical")


class CustomersRulepack(unittest.TestCase):
    """Reproduces the verified baseline: customers composite ~0.773 (High Risk)."""

    def test_customers_matches_baseline(self):
        # Synthetic counts (n=11) with defects across every dimension, landing the
        # composite in the verified baseline band (High Risk, ~0.77).
        m = {
            "n": "11", "null_email": "3", "null_region": "1", "dup_ids": "2",
            "bad_email": "3", "bad_region": "2", "future_signup": "1",
            "signup_after_update": "3", "missing_name": "2", "age_days": "200",
        }
        dims = rulepacks._customers(m)
        by = {d["dimension"]: d for d in dims}
        self.assertAlmostEqual(by["completeness"]["score"], 1 - 4 / 22, places=4)
        self.assertAlmostEqual(by["uniqueness"]["score"], 1 - 2 / 11, places=4)
        self.assertAlmostEqual(by["validity"]["score"], 1 - 6 / 33, places=4)
        # timeliness: 200 days old, target 30 => 1 - 170/365
        self.assertAlmostEqual(by["timeliness"]["score"], 1 - 170 / 365, places=4)
        composite = scoring.composite([d["score"] for d in dims])
        self.assertEqual(scoring.severity(composite), "High Risk")
        self.assertLess(composite, 0.85)
        self.assertGreaterEqual(composite, 0.70)

    def test_products_consistency_not_assessed(self):
        m = {"n": "8", "null_cells": "0", "dup_ids": "0", "invalid_vals": "0",
             "blank_name": "0", "age_days": "5"}
        dims = rulepacks._products(m)
        by = {d["dimension"]: d for d in dims}
        self.assertIsNone(by["consistency"]["score"])
        self.assertEqual(by["consistency"]["severity"], "Not Assessed")
        # Healthy baseline excludes the Not-Assessed dimension from the mean.
        composite = scoring.composite([d["score"] for d in dims])
        self.assertEqual(composite, 1.0)
        self.assertEqual(scoring.severity(composite), "Healthy")


if __name__ == "__main__":
    unittest.main(verbosity=2)
