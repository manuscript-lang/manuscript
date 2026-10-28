import json
import subprocess
from pathlib import Path
import sys
import unittest

from stdlib_results import case_labels, read_cases


class ResultValidation(unittest.TestCase):
    def test_invalid_numeric_fields_in_both_consumers(self):
        for field in ("median_ns", "min_ns", "max_ns", "mean_ns", "stddev_ns",
                      "operations", "iterations", "samples"):
            invalid = [float("nan"), float("inf"), -1, True, "2", None]
            if not field.endswith("_ns"):
                invalid += [0, 1.5]
            for value in invalid:
                with self.subTest(field=field, value=value):
                    stats = dict(operations=10, iterations=1, samples=3,
                                 median_ns=2, min_ns=1, max_ns=3)
                    stats[field] = value
                    output = json.dumps({"benches": [{"name": "a.ms::a", "status": "passed", "stats": stats}]})
                    with self.assertRaises((ValueError, TypeError)):
                        read_cases(output)
                    result = subprocess.run([sys.executable, str(Path(__file__).with_name("stdlib_bench_table.py"))],
                                            input=output, capture_output=True, text=True, timeout=5)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")

    def test_large_json_exponent_and_finite_zero(self):
        for token in ("1e999", "NaN", "Infinity", "-Infinity"):
            with self.assertRaises(ValueError):
                read_cases('{"benches":[{"name":"a","status":"passed","stats":{"operations":1,"median_ns":' + token + '}}]}')
        cases = read_cases('{"benches":[{"name":"a","status":"passed","stats":{"operations":1,"median_ns":0}}]}')
        self.assertEqual(cases["a"]["stats"]["median_ns"], 0)

    def test_labels_disambiguate_only_collisions(self):
        self.assertEqual(case_labels(["a.ms::x", "b.ms::x", "b.ms::y"]),
                         {"a.ms::x": "a.ms::x", "b.ms::x": "b.ms::x", "b.ms::y": "y"})
