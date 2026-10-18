"""Capture actual CLI-generated Debug Go and compile construction benchmarks.

Run cli_pairs.py first, preserving MANUSCRIPT_CACHE_DIR. Use the repository's
bundled toolchain for --go and the corresponding repository checkout for --repo.
Generated source and its SHA256 are retained beside each benchmark executable.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--sizes", default="16000,100000")
    parser.add_argument("--go", required=True)
    parser.add_argument("--repo", required=True)
    args = parser.parse_args()
    root = Path(args.output).resolve()
    files = list(Path(args.cache).glob("manuscript/workspaces/*/apps/*/main.go"))
    for n in (int(size) for size in args.sizes.split(",")):
        if n <= 1024:
            parser.error("construction comparison requires a transformed list")
        for variant in ("baseline", "prototype"):
            matches = []
            for file in files:
                source = file.read_text()
                if str(root / str(n) / "source.ms") not in source:
                    continue
                transformed = "debugLiteralData1" in source
                if transformed != (variant == "prototype"):
                    continue
                if transformed and "Items: append([]rt.Value(nil), debugLiteralData1[:]...)" not in source:
                    continue
                matches.append(file)
            original = max(matches, key=lambda file: file.stat().st_mtime_ns)
            source = original.read_text()
            # The emitter creates values() as its first source function.
            symbol = re.search(r"(?m)^\t(\w+) = func\(\) rt.Function \{", source)[1]
            directory = root / str(n) / variant
            directory.mkdir(exist_ok=True)
            (directory / "main.go").write_text(source)
            (directory / "provenance.json").write_text(json.dumps(dict(
                cache_source=str(original), source_sha256=hashlib.sha256(source.encode()).hexdigest(),
                elements=n, variant=variant, symbol=symbol,
            ), indent=2) + "\n")
            harness = f'''package main
import("testing"; rt "github.com/manuscript-lang/manuscript/pkg/runtime")
var sink rt.Value
func TestResult(t *testing.T) {{
 initialize()
 ctx:=rt.RootExecution()
 first:=rt.Invoke(ctx,{symbol},nil).(*rt.List)
 second:=rt.Invoke(ctx,{symbol},nil).(*rt.List)
 if len(first.Items)!={n} || len(second.Items)!={n} {{t.Fatal("length")}}
 for i,v:=range first.Items {{if int64(rt.IntValue(v))!=int64(i) {{t.Fatal(i,v)}}}}
 first.Items[0]=first.Items[{n}-1]
 if rt.IntValue(second.Items[0])!=0 {{t.Fatal("shared storage")}}
}}
func BenchmarkLiteral(b *testing.B) {{
 initialize();ctx:=rt.RootExecution();b.ReportAllocs();b.ResetTimer()
 for i:=0;i<b.N;i++ {{sink=rt.Invoke(ctx,{symbol},nil)}}
}}
'''
            (directory / "program_test.go").write_text(harness)
            with (directory / "test-build.log").open("w") as log:
                subprocess.run([args.go, "test", "-mod=vendor", "-tags=ms_lean",
                                "-gcflags=all=-N -l", "-ldflags=-compressdwarf=false",
                                "-c", "-o", str(directory / "runtime.test"),
                                str(directory / "main.go"), str(directory / "program_test.go")],
                               cwd=args.repo, stdout=log, stderr=log, check=True)
            print(n, variant, original, flush=True)


if __name__ == "__main__":
    main()
