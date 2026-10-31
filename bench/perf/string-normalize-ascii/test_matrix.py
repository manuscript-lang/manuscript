"""Exercise evidence validation with controlled producers and damaged records."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("analyze_matrix", HERE / "analyze_matrix.py")
ANALYSIS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ANALYSIS)


class MatrixEvidenceTests(unittest.TestCase):
    def run_producers(self, second_output):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        good = "case,input_bytes,iterations,elapsed_ns,checksum\ntiny,1,2,20,4\n"
        programs = {}
        for label, output in [("a", good), ("b", second_output)]:
            script = root / label
            script.write_text("#!/usr/bin/env python3\nprint(" + repr(output) + ", end='')\n")
            script.chmod(0o700)
            programs[label] = str(script)
        (root / "programs.json").write_text(json.dumps(programs))
        identities = root / "identities.json"
        identities.write_text(json.dumps({"tiny": [1, 2, 4]}))
        result = subprocess.run([sys.executable, str(HERE / "compare_matrix.py"),
                                 str(root / "programs.json"), str(identities),
                                 str(root / "result"), "--cpu", str(min(os.sched_getaffinity(0)))],
                                capture_output=True, text=True)
        return result, root, identities

    def test_valid_balanced_matrix_and_paired_report(self):
        result, root, identities = self.run_producers(
            "case,input_bytes,iterations,elapsed_ns,checksum\ntiny,1,2,24,4\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = ANALYSIS.comparisons(root / "result", identities)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["rounds"], 4)
        self.assertEqual(rows[0]["paired_median_delta_ns"], 2)
        self.assertEqual(rows[0]["slower_pairs"], 4)

    def test_failed_producer_never_publishes_summary(self):
        for output in ["", "case,input_bytes,iterations,elapsed_ns,checksum\n",
                       "case,input_bytes,iterations,elapsed_ns,checksum\ntiny,1,2,24,5\n",
                       "case,input_bytes,iterations,elapsed_ns,checksum\ntiny,1,2,24,4\ntiny,1,2,24,4\n"]:
            with self.subTest(output=output):
                result, root, _ = self.run_producers(output)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / "result/summary.csv").exists())
                self.assertFalse(json.loads((root / "result/record.json").read_text())["complete"])

    def test_incomplete_or_missing_evidence_rejected(self):
        _, root, identities = self.run_producers(
            "case,input_bytes,iterations,elapsed_ns,checksum\ntiny,1,2,24,4\n")
        samples = root / "result/samples.csv"
        samples.write_text("\n".join(samples.read_text().splitlines()[:-1]) + "\n")
        with self.assertRaisesRegex(ValueError, "missing samples"):
            ANALYSIS.comparisons(root / "result", identities)
        record = root / "result/record.json"
        data = json.loads(record.read_text())
        data["complete"] = False
        record.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "incomplete"):
            ANALYSIS.comparisons(root / "result", identities)


if __name__ == "__main__":
    unittest.main()
