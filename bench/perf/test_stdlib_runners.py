"""Exercise the real wrappers with fixed-output producers, without native builds."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class Producers(unittest.TestCase):
    def test_failed_producer_never_prints_or_writes_a_report(self):
        case = {"name": "m.ms::a", "status": "passed",
                "stats": {"operations": 10, "median_ns": 2, "min_ns": 1, "max_ns": 3}}
        for status, cases in ((0, [case]), (42, [case]), (0, []), (42, [])):
            with self.subTest(status=status, empty=not cases), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                producer = root / "producer"
                producer.write_text(f"#!{sys.executable}\nimport sys\nprint(" +
                                    repr(json.dumps({"benches": cases, "diagnostics": []})) +
                                    f")\nprint('producer detail', file=sys.stderr)\nsys.exit({status})\n")
                producer.chmod(0o755)
                commands = [
                    ["sh", str(HERE / "stdlib-bench.sh"), "1"],
                    [sys.executable, str(HERE / "compare_stdlib.py"), "--before", str(producer),
                     "--after", str(producer), "--output", str(root / "report"),
                     "--repeats", "1", "--samples", "1"],
                ]
                for command in commands:
                    result = subprocess.run(command, env=os.environ | {"MS": str(producer)},
                                            capture_output=True, text=True, timeout=10)
                    succeeds = status == 0 and bool(cases)
                    self.assertEqual(result.returncode == 0, succeeds, result.stderr)
                    if not succeeds:
                        self.assertEqual(result.stdout, "")
                        self.assertFalse((root / "report").exists())

    def test_qualified_display_collisions_preserve_every_summary_entry(self):
        names = ["a.ms::x", "b.ms::x", "c.ms::a.ms::x"]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            producer = root / "producer"
            cases = [{"name": name, "status": "passed",
                      "stats": {"operations": 10, "median_ns": 2}} for name in names]
            producer.write_text(f"#!{sys.executable}\nprint(" + repr(json.dumps({"benches": cases})) + ")\n")
            producer.chmod(0o755)
            result = subprocess.run([sys.executable, str(HERE / "compare_stdlib.py"),
                "--before", str(producer), "--after", str(producer), "--output", str(root / "report"),
                "--repeats", "1"], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads((root / "report" / "summary.json").read_text())
            self.assertEqual(set(summary), set(names))
