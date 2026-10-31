"""Exercise workload comparisons without native compiler dependencies."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from measure import VERSIONS, measure

HERE = Path(__file__).resolve().parent


def producer(path, version, mode="valid"):
    path.write_text(f"#!{sys.executable}\n" + f"version = {version!r}\nmode = {mode!r}\n" + '''from pathlib import Path
import sys
counter = Path("count")
count = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(count + 1))
with Path("../order").open("a") as stream: stream.write(version + "\\n")
text = "correct"
if mode == "wrong" or (mode == "wrong_first_trial" and count == 1): text = "WRONG!!"
print(text)
if mode == "failed" or (mode == "failed_first_trial" and count == 1): sys.exit(42)
''')
    path.chmod(0o755)


def programs(root, mode="valid", changed="rs"):
    (root / "in").write_text("input\n")
    for version in VERSIONS:
        (root / version).mkdir()
        producer(root / version / "app", version, mode if version == changed else "valid")


class Measurements(unittest.TestCase):
    def test_every_trial_rotates_and_retains_samples_and_identities(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            programs(root)
            row = measure(root, 3, "workload")
            self.assertTrue(row.startswith("workload"))
            order = (root / "order").read_text().splitlines()
            self.assertEqual(order, ["go", "ms", "rs", "ms", "go", "rs",
                                     "go", "rs", "ms", "rs", "ms", "go"])
            raw = json.loads((root / "samples.json").read_text())
            self.assertEqual(len(raw["samples"]), 9)
            self.assertEqual({(s["trial"], s["version"]) for s in raw["samples"]},
                             {(i, v) for i in range(3) for v in VERSIONS})
            self.assertTrue(all(s["elapsed_ns"] > 0 for s in raw["samples"]))
            self.assertEqual(set(raw["binaries_sha256"]), set(VERSIONS))
            self.assertEqual(len(raw["input_sha256"]), 64)
            self.assertEqual(len(raw["output_sha256"]), 64)

    def test_rejects_wrong_or_failed_warmup_and_early_trial_for_every_version(self):
        for version in VERSIONS:
            for mode in ("wrong", "wrong_first_trial", "failed", "failed_first_trial"):
                with self.subTest(version=version, mode=mode), tempfile.TemporaryDirectory() as temp:
                    root = Path(temp)
                    programs(root, mode, version)
                    with self.assertRaises(ValueError):
                        measure(root, 2, "workload")
                    self.assertFalse((root / "samples.json").exists())

    def test_rejects_invalid_repeat_count(self):
        with self.assertRaises(ValueError):
            measure(Path("missing"), 0, "workload")
        for repeats in ("0", "00", "abc", "-1"):
            with self.subTest(repeats=repeats):
                result = subprocess.run(["sh", str(HERE / "run.sh"), repeats],
                    env=os.environ | {"MS": "/must-not-run"}, capture_output=True,
                    text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("repeats must be a positive integer", result.stderr)

    def test_real_wrapper_checks_rust_and_early_trials_and_relative_ms(self):
        for mode in ("valid", "wrong", "wrong_first_trial", "failed_first_trial", "later_wrong"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                scripts = root / "bench/perf/workloads"
                scripts.mkdir(parents=True)
                for name in ("run.sh", "measure.py"):
                    shutil.copy(HERE / name, scripts / name)
                names = ("c03-csv-group-sum", "c05-calculator") if mode == "later_wrong" else ("c03-csv-group-sum",)
                for name in names:
                    challenge = root / "bench/agent/challenges" / name
                    for language, filename in (("ms", "main.ms.ref"), ("go", "main.go.ref"), ("rust", "main.rs.ref")):
                        directory = challenge / "solutions" / language
                        directory.mkdir(parents=True)
                        (directory / filename).write_text("placeholder\n")
                    (challenge / "hidden").mkdir()
                    (challenge / "hidden/cases.json").write_text('[{"stdin":"row\\n"}]')
                template = root / "bench/agent/templates/ms"
                template.mkdir(parents=True)
                (template / "ms.toml").write_text("placeholder\n")
                tools = root / "bin"
                tools.mkdir()
                compiler = f"#!{sys.executable}\n" + '''from pathlib import Path
import importlib.util
import os
import sys
if sys.argv[1:3] == ["mod", "init"]: sys.exit(0)
sys.path.insert(0, str(Path(os.environ["TEST_PRODUCERS"]).parent))
spec = importlib.util.spec_from_file_location("test_measure", os.environ["TEST_PRODUCERS"])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
version = Path.cwd().name
mode = os.environ["TEST_MODE"] if version == "rs" else "valid"
if mode == "later_wrong": mode = "wrong" if Path.cwd().parent.name == "c05-calculator" else "valid"
module.producer(Path(sys.argv[sys.argv.index("-o") + 1]), version, mode)
'''
                for name in ("go", "rustc", "ms"):
                    path = tools / name
                    path.write_text(compiler)
                    path.chmod(0o755)
                env = os.environ | {"MS": "bin/ms", "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                    "TEST_PRODUCERS": str(Path(__file__).resolve()), "TEST_MODE": mode,
                    "BENCH_OUTPUT": str(root / "evidence")}
                result = subprocess.run(["sh", str(scripts / "run.sh"), "2"], cwd=root,
                                        env=env, text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode == 0, mode == "valid", result.stderr)
                if mode == "valid":
                    self.assertIn("c03-csv-group-sum", result.stdout)
                    self.assertEqual(len(list((root / "evidence").glob("*/c03*/samples.json"))), 1)
                else:
                    self.assertEqual(result.stdout, "")
                    self.assertIn("rs", result.stderr)
                    self.assertEqual(list((root / "evidence").glob("*/table.txt")), [])


if __name__ == "__main__":
    unittest.main()
