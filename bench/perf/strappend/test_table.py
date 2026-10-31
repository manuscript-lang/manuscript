import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from table import CHECKSUMS, summarize


def sample(trial, version, elapsed=100):
    return [f"{trial} {version} {name} {elapsed} # {checksum}\n" for name, checksum in CHECKSUMS.items()]


class Samples(unittest.TestCase):
    def test_minima_and_reordered_samples(self):
        lines = sample(0, "ms", 200) + sample(0, "rust") + sample(1, "ms", 50) + sample(1, "rust", 100)
        result = summarize(reversed(lines), 2)
        self.assertEqual(result.count("0.50x"), len(CHECKSUMS))

    def test_invalid_evidence(self):
        valid = sample(0, "ms") + sample(0, "rust")
        for lines in ([], valid[:-1], valid + valid[:1], sample(0, "ms"),
                      [valid[0].replace("# 40000000", "# -1")] + valid[1:],
                      sample(0, "ms", 0) + sample(0, "rust"),
                      sample(0, "ms", -1) + sample(0, "rust"),
                      [valid[0].replace("100 #", "nan #")] + valid[1:]):
            with self.subTest(lines=lines[:1]), self.assertRaises(ValueError):
                summarize(lines, 1)
        with self.assertRaises(ValueError):
            summarize(valid, 2)

    def test_real_runner_checks_exit_status_and_checksum(self):
        with tempfile.TemporaryDirectory() as temp:
            compiler = Path(temp) / "compiler"
            compiler.write_text(f"#!{sys.executable}\n" + '''import os, pathlib, sys
mode = os.environ['TEST_MODE']
rows = ''' + repr([f"{name}\t100\t# {checksum}" for name, checksum in CHECKSUMS.items()]) + '''
if mode == 'checksum': rows = [row.split('#')[0] + '# -1' for row in rows]
if mode == 'empty': rows = []
code = '#!' + sys.executable + '\\nimport sys\\n'
code += ''.join('print(' + repr(row) + ')\\n' for row in rows)
code += 'sys.exit(' + ('42' if mode == 'failed' else '0') + ')\\n'
output = pathlib.Path(sys.argv[sys.argv.index('-o')+1])
output.write_text(code)
output.chmod(0o755)
''')
            compiler.chmod(0o755)
            for mode in ("valid", "failed", "checksum", "empty"):
                with self.subTest(mode=mode):
                    r = subprocess.run(["sh", str(Path(__file__).with_name("run.sh")), "2"],
                        env=os.environ | {"MS": str(compiler), "RUSTC": str(compiler), "TEST_MODE": mode},
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(r.returncode == 0, mode == "valid", r.stderr)
                    if mode != "valid": self.assertEqual(r.stdout, "")
