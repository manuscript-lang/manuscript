"""Exercise data-structure accounting with controlled, non-native producers."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("datastructure_table", HERE / "datastructures/table.py")
TABLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TABLE)


def trial(version, per=100):
    return [f"{version} {name} {ops} {per * ops}\n"
            for name, ops in TABLE.OPERATIONS.items() if name in TABLE.operations(version)] + [
                f"{version} # end\n"]


def report_row(report, name="list_append"):
    return next(line.split()[1:] for line in report.splitlines() if line.startswith(name + " "))


class DatastructureTrials(unittest.TestCase):
    def test_minimum_and_legitimate_missing_go_operation(self):
        lines = sum((trial(v) for v in TABLE.VERSIONS), [])
        lines += sum((trial(v, 50) for v in ("go", "rs", "ms")), [])
        report = TABLE.summarize(lines, 2)
        self.assertIn("Minimum of 2 rotating trials", report)
        self.assertEqual(report_row(report), ["50.0", "50.0", "50.0", "1.00", "1.00"])
        self.assertEqual(report_row(report, "sorted_map_add_contains"),
                         ["50.0", "-", "50.0", "-", "1.00"])

    def test_zero_samples_remain_visible_without_ratios(self):
        for zero_version in TABLE.VERSIONS:
            with self.subTest(version=zero_version):
                lines = sum((trial(v, 0 if v == zero_version else 100) for v in TABLE.VERSIONS), [])
                row = report_row(TABLE.summarize(lines, 1))
                self.assertEqual(row[TABLE.VERSIONS.index(zero_version)], "0.0")
                self.assertEqual(row[3], "-" if zero_version in ("ms", "go") else "1.00")
                self.assertEqual(row[4], "-" if zero_version in ("ms", "rs") else "1.00")

    def test_rejects_invalid_evidence(self):
        good = sum((trial(v) for v in TABLE.VERSIONS), [])
        go_end = good.index("go # end\n")
        bad = {
            "empty": [],
            "unfinished": good[:-1],
            "extra trial": good + trial("ms"),
            "missing everywhere": [line for line in good if "list_append" not in line],
            "missing first ms sample": good[1:] + good,
            "duplicate": good[:1] + good,
            "missing version": [line for line in good if not line.startswith("go ")],
            "missing boundary": [line for line in good if line != "ms # end\n"],
            "unknown operation": [good[0].replace("list_append", "unknown")] + good[1:],
            "unknown version": [good[0].replace("ms ", "unknown ")] + good[1:],
            "unexpected go sorted map": good[:go_end] + ["go sorted_map_add_contains 600000 1\n"] + good[go_end:],
            "changed count": ["ms list_append 100000000 100000000\n"] + good[1:],
            "zero count": ["ms list_append 0 100000000\n"] + good[1:],
            "negative count": ["ms list_append -1000000 100000000\n"] + good[1:],
            "negative time": ["ms list_append 1000000 -1\n"] + good[1:],
            "noninteger time": ["ms list_append 1000000 nan\n"] + good[1:],
            "blank": good + ["\n"],
        }
        for name, lines in bad.items():
            with self.subTest(case=name), self.assertRaises(ValueError):
                TABLE.summarize(lines, 2 if name == "missing first ms sample" else 1)
        for repeats in (0, -1):
            with self.subTest(repeats=repeats), self.assertRaises(ValueError):
                TABLE.summarize(good, repeats)

    def test_late_cli_error_has_no_partial_report(self):
        lines = sum((trial(v) for v in TABLE.VERSIONS), [])
        lines[-2] = "rs sorted_map_add_contains 600000 -1\n"
        with tempfile.TemporaryDirectory() as temp:
            raw = Path(temp) / "raw.txt"
            raw.write_text("".join(lines))
            result = subprocess.run([sys.executable, str(HERE / "datastructures/table.py"),
                                     str(raw), "1"], capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("invalid count or timing", result.stderr)


class DatastructureProducers(unittest.TestCase):
    def test_real_runner_validates_each_trial_and_preserves_producer_failures(self):
        # These build tools create Python fixtures, never compile benchmark sources.
        tool_body = '''import json, os
from pathlib import Path
import sys
args = sys.argv[1:]
output = Path(args[args.index("-o") + 1])
rows = json.loads(os.environ["TEST_ROWS"])
version = output.name
if version == "go": rows.pop("sorted_map_add_contains")
producer = "#!" + sys.executable + "\\n"
producer += "rows = " + repr(rows) + "\\nversion = " + repr(version) + "\\n"
producer += ''' + repr('''import os
from pathlib import Path
import sys
marker = Path(sys.argv[0] + ".count")
count = int(marker.read_text()) if marker.exists() else 0
marker.write_text(str(count + 1))
with open(os.environ["TEST_LOG"], "a") as log: log.write(version + "\\n")
mode = os.environ["TEST_MODE"] if version == os.environ["TEST_VERSION"] else "valid"
for name, ops in rows.items():
    if mode == "empty": continue
    if mode == "missing-first" and count == 0 and name == "list_append": continue
    ns = ops * 100
    if mode == "changed-ops" and name == "list_append": ops *= 100
    if mode == "negative" and name == "list_append": ns = -1
    print(name, ops, ns)
    if mode == "duplicate" and name == "list_append": print(name, ops, ns)
if mode == "failed": sys.exit(42)
''') + '''
output.write_text(producer)
output.chmod(0o755)
'''
        cases = [("valid", "ms")] + [(mode, version) for mode in
                 ("failed", "empty", "missing-first", "duplicate", "changed-ops", "negative")
                 for version in TABLE.VERSIONS]
        for mode, version in cases:
            with self.subTest(mode=mode, version=version), tempfile.TemporaryDirectory() as temp:
                tool = Path(temp) / "tool"
                tool.write_text(f"#!{sys.executable}\n" + tool_body)
                tool.chmod(0o755)
                for compiler in ("go", "rustc"):
                    (Path(temp) / compiler).symlink_to(tool)
                log = Path(temp) / "log.txt"
                env = os.environ | {"MS": str(tool), "PATH": temp + os.pathsep + os.environ["PATH"],
                    "TEST_ROWS": json.dumps(TABLE.OPERATIONS), "TEST_MODE": mode,
                    "TEST_VERSION": version, "TEST_LOG": str(log)}
                result = subprocess.run(["sh", str(HERE / "datastructures/run.sh"), "2"],
                    env=env, capture_output=True, text=True, timeout=20)
                if mode == "valid":
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(log.read_text().splitlines(), ["ms", "go", "rs", "go", "rs", "ms"])
                    self.assertEqual(report_row(result.stdout, "sorted_map_add_contains"),
                                     ["100.0", "-", "100.0", "-", "1.00"])
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    if mode == "failed":
                        self.assertEqual(result.returncode, 42)

    def test_invalid_repeats_fail_before_building(self):
        for repeats in ("0", "00", "abc", "-1"):
            with self.subTest(repeats=repeats):
                result = subprocess.run(["sh", str(HERE / "datastructures/run.sh"), repeats],
                    env=os.environ | {"MS": "/must-not-run"},
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("repeats must be a positive integer", result.stderr)


if __name__ == "__main__":
    unittest.main()
