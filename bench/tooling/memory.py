#!/usr/bin/env python3
"""Run the identical retained-heap probe in an old or new LSP checkout."""
import argparse
import json
import pathlib
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument("--repo", type=pathlib.Path, required=True)
p.add_argument("--out", type=pathlib.Path, required=True)
p.add_argument("--count", type=int, default=3)
args = p.parse_args()
repo = args.repo.resolve()
probe = pathlib.Path(__file__).with_name("snapshot_memory_test.go.txt").resolve()
args.out.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="manuscript-heap-") as temporary:
    overlay = pathlib.Path(temporary) / "overlay.json"
    overlay.write_text(json.dumps({"Replace": {str(repo / "pkg/tooling/lsp/snapshot_memory_review_test.go"): str(probe)}}))
    run = subprocess.run([str(repo / "toolchain/go/bin/go"), "test", f"-overlay={overlay}",
                          "./pkg/tooling/lsp", "-run", "^TestSnapshotMemoryEvidence$",
                          f"-count={args.count}", "-v"], cwd=repo, text=True, capture_output=True)
    args.out.write_text(run.stdout + run.stderr)
    print(run.stdout, end="")
    print(run.stderr, end="")
    raise SystemExit(run.returncode)
