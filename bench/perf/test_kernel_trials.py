"""Reject failed producers and incomplete evidence in both whole-kernel suites."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from table import ABLATIONS, C_VERSIONS, SUITES, VERSIONS, summarize

HERE = Path(__file__).resolve().parent


def trial(version, suite="kernels", micros=100):
    return [f"{version} {name} {micros} 1\n" for name in SUITES[suite]] + [
        f"{version} # end\n"]


class KernelTrials(unittest.TestCase):
    def test_complete_rotating_trials_preserve_minimum_and_columns(self):
        for suite in SUITES:
            versions = VERSIONS + C_VERSIONS if suite == "kernels" else VERSIONS
            lines = sum((trial(v, suite, 100) for v in versions), [])
            lines += sum((trial(v, suite, 50) for v in versions[1:] + versions[:1]), [])
            report = summarize(lines, suite, 2, versions)
            self.assertIn("Minimum of 2 rotating runs", report)
            self.assertIn("| ms / rust | ms / rust-checked |", report)
            self.assertIn(f"| {SUITES[suite][0]} | 50 | 50 | 1.00x", report)

    def test_ablation_versions_and_folded_times(self):
        versions = VERSIONS + C_VERSIONS + ABLATIONS
        lines = sum((trial(v, micros=0) for v in versions), [])
        report = summarize(lines, "kernels", 1, versions)
        self.assertIn("c-ms-unchecked us", report)
        self.assertIn("folded", report)

    def test_rejects_invalid_evidence(self):
        versions = VERSIONS + C_VERSIONS
        good = sum((trial(v) for v in versions), [])
        omitted = SUITES["kernels"][0]
        bad_samples = [
            [], good[:-1], good + trial("ms"),  # Empty, truncated, extra trial.
            [line for line in good if omitted not in line],  # Missing everywhere.
            good[1:], [good[0]] + good,  # Missing or duplicate in one trial.
            [line for line in good if not line.startswith("c ")],  # Missing version.
            [good[0].replace("100", "-1")] + good[1:],
            [good[0].replace("100", "nan")] + good[1:],
            [good[0].replace(" 1\n", " 2\n")] + good[1:],
            [good[0].replace(omitted, "unknown")] + good[1:],
            [good[0].replace("go ", "unknown ")] + good[1:],
            ["go # end\n"] + good,
            good + ["unrecognized output\n"],
        ]
        for lines in bad_samples:
            with self.subTest(lines=lines):
                with self.assertRaises(ValueError):
                    summarize(lines, "kernels", 1, versions)
        with self.assertRaises(ValueError):
            summarize(good, "kernels", 0, versions)
        with self.assertRaises(ValueError):
            summarize(good, "kernels", 1, VERSIONS)

    def test_invalid_cli_input_emits_no_partial_report(self):
        versions = VERSIONS + C_VERSIONS
        lines = sum((trial(v) for v in versions), [])
        # A late checksum mismatch used to print earlier valid rows first.
        lines[-2] = lines[-2].replace(" 1\n", " 2\n")
        with tempfile.TemporaryDirectory() as temp:
            raw = Path(temp) / "raw.txt"
            raw.write_text("".join(lines))
            result = subprocess.run([sys.executable, str(HERE / "table.py"),
                str(raw), "kernels", "1", " ".join(versions)],
                capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("checksums differ", result.stderr)


class KernelProducers(unittest.TestCase):
    def test_real_runners_check_exit_status_and_complete_trials(self):
        # Fake build tools emit fixed-output executables. Exercise the actual shell
        # wrappers without requiring Manuscript, Rust or Go to be installed.
        for suite in SUITES:
            for mode in ("valid", "failed", "empty", "duplicate"):
                with self.subTest(suite=suite, mode=mode), tempfile.TemporaryDirectory() as temp:
                    tool = Path(temp) / "tool"
                    tool.write_text(f"#!{sys.executable}\n" + '''import os
from pathlib import Path
import sys
args = sys.argv[1:]
output = Path(args[args.index("-o") + 1])
producer = "#!" + sys.executable + "\\n" + "import sys\\n"
rows = os.environ["TEST_ROWS"].splitlines()
if output.resolve().parent.name == "ms":
    mode = os.environ["TEST_MODE"]
    if mode == "empty": rows = []
    if mode == "duplicate": rows += rows[:1]
    status = 42 if mode == "failed" else 0
else:
    status = 0
producer += "print(" + repr("\\n".join(rows)) + ")\\n" if rows else ""
producer += "sys.exit(" + str(status) + ")\\n"
output.write_text(producer)
output.chmod(0o755)
''')
                    tool.chmod(0o755)
                    rows = "\n".join(f"{name} 100 1" for name in SUITES[suite])
                    env = os.environ | {"MS": str(tool), "GO": str(tool),
                        "RUSTC": str(tool), "CC": str(tool),
                        "TEST_ROWS": rows, "TEST_MODE": mode}
                    result = subprocess.run(["sh", str(HERE / suite / "run.sh"), "2"],
                        env=env, capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode == 0, mode == "valid", result.stderr)
                    if mode == "valid":
                        self.assertIn("Complete trials and checksums verified", result.stdout)
                    else:
                        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
