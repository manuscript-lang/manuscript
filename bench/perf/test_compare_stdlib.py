import json
import unittest

from compare_stdlib import parse_sample


def document(*cases, diagnostics=()):
    benches = [
        {"name": f"m.ms::{name}", "status": status,
         "stats": {"operations": operations, "median_ns": median}}
        for name, status, operations, median in cases
    ]
    return json.dumps({"benches": benches, "diagnostics": list(diagnostics)})


class LibrarySamples(unittest.TestCase):
    def test_reads_operations_and_median_per_case(self):
        rows, identity = parse_sample(document(("a", "passed", 10, 2.5), ("b", "passed", 1, 0)))
        self.assertEqual(rows, {"a": (10, 2.5), "b": (1, 0)})
        self.assertEqual(identity, {"a": 10, "b": 1})

    def test_rejects_changed_cases_or_operation_counts(self):
        _, expected = parse_sample(document(("a", "passed", 10, 2)))
        for text in (document(("a", "passed", 11, 2)), document(("b", "passed", 10, 2)),
                     document(("a", "passed", 10, 2), ("b", "passed", 1, 2))):
            with self.assertRaises(ValueError):
                parse_sample(text, expected)

    def test_rejects_failed_duplicate_empty_or_uncompiled_runs(self):
        for text in (document(("a", "failed", 10, 2)),
                     document(("a", "passed", 10, 2), ("a", "passed", 10, 2)),
                     document(),
                     document(diagnostics=[{"message": "does not compile"}])):
            with self.assertRaises(ValueError):
                parse_sample(text)

    def test_rejects_impossible_measurements(self):
        for text in (document(("a", "passed", 0, 2)), document(("a", "passed", 10, -1))):
            with self.assertRaises(ValueError):
                parse_sample(text)


if __name__ == "__main__":
    unittest.main()
