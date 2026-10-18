#!/usr/bin/env python3
"""Map retained external probes into an explicitly selected checkout."""
import argparse
import json
import pathlib

p = argparse.ArgumentParser()
p.add_argument("--repo", type=pathlib.Path, required=True)
p.add_argument("--out", type=pathlib.Path, required=True)
a = p.parse_args()
repo = a.repo.resolve()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=True)
here = pathlib.Path(__file__).resolve().parent
mapping = {
    str(repo / "pkg/tooling/zz_non_lsp_probe_test.go"): str(here / "tooling_probe_test.go.txt"),
    str(repo / "pkg/tooling/guide/zz_non_lsp_probe_test.go"): str(here / "guide_probe_test.go.txt"),
}
(out / "overlay.json").write_text(json.dumps({"Replace": mapping}, indent=2) + "\n")
print(out / "overlay.json")
