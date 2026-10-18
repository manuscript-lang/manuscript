#!/usr/bin/env python3
"""Verify Result-returning assertion controls; timings are not benchmarks."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument("--binary", type=pathlib.Path, required=True)
p.add_argument("--out", type=pathlib.Path, required=True)
args = p.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
rows = []
for name, statement, expected in [("positive", "try assert_true(true)", 0),
                                  ("negative", "try assert_true(false)", 1),
                                  ("ignored-result", "assert_true(false)", 0)]:
    path = args.out / f"{name}.ms"
    path.write_text(f'import assert_true from "@std/testing.ms"\n\ntest "{name}":\n    {statement}\n')
    run = subprocess.run([str(args.binary.resolve()), "test", str(path.resolve())],
                         capture_output=True, text=True, timeout=180)
    row = {"name": name, "expected_exit": expected, "actual_exit": run.returncode,
           "stdout": run.stdout, "stderr": run.stderr}
    rows.append(row)
    (args.out / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    print(json.dumps(row), flush=True)
    assert run.returncode == expected, row
