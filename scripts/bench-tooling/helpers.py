#!/usr/bin/env python3
"""Run the same helper benchmark sources against old/new LSP implementations."""
import argparse
import json
import pathlib
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument("--repo", type=pathlib.Path, required=True)
p.add_argument("--out", type=pathlib.Path, required=True)
p.add_argument("--pattern", default="^Benchmark(SemanticProject|Review(Index|DeclarationDocs|Semantic|LongLine))$")
p.add_argument("--count", type=int, default=2)
p.add_argument("--benchtime", default="300ms")
args = p.parse_args()
repo = args.repo.resolve()
here = pathlib.Path(__file__).resolve().parent
args.out.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="manuscript-helpers-") as temporary:
    overlay = pathlib.Path(temporary) / "overlay.json"
    overlay.write_text(json.dumps({"Replace": {
        str(repo / "pkg/tooling/lsp/review_perf_test.go"): str(here / "helper_bench_test.go.txt"),
        str(repo / "pkg/tooling/lsp/performance_test.go"): str(here / "semantic_project_test.go.txt"),
    }}))
    run = subprocess.run([str(repo / "toolchain/go/bin/go"), "test", f"-overlay={overlay}",
                          "./pkg/tooling/lsp", "-run", "^$", "-bench", args.pattern, "-benchmem",
                          f"-count={args.count}", f"-benchtime={args.benchtime}"],
                         cwd=repo, text=True, capture_output=True)
    args.out.write_text(run.stdout + run.stderr)
    print(run.stdout, end="")
    print(run.stderr, end="")
    raise SystemExit(run.returncode)
