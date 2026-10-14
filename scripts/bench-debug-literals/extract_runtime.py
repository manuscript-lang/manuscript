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
    parser.add_argument("--variants", default="baseline,prototype")
    parser.add_argument("--elements", default="scalar", choices=("scalar", "calls"))
    parser.add_argument("--build-type", default="Debug",
                        choices=("Debug", "Release", "RelWithDebInfo", "MinSizeRel"))
    args = parser.parse_args()
    root = Path(args.output).resolve()
    files = list(Path(args.cache).glob("manuscript/workspaces/*/apps/*/main.go"))
    for n in (int(size) for size in args.sizes.split(",")):
        if n <= 1024:
            parser.error("construction comparison requires a transformed list")
        for variant in args.variants.split(","):
            matches = []
            for file in files:
                source = file.read_text()
                # Release rewrites absolute source paths for reproducibility.
                # Match the explicit expected length in main as well as the
                # original path; data itself only contains values below n.
                absolute_source = str(root / str(n) / "source.ms") in source
                declaration_line = 3 if args.elements == "calls" else 2
                relative_source = (f'"source.ms:{declaration_line}:16"' in source and
                                   re.search(r"IntSubtract[^\n]*int64\(" + str(n) + r"\)", source))
                if not absolute_source and not relative_source:
                    continue
                transformed = ("debugLiteralData1" in source if args.build_type == "Debug"
                               else "literalData1" in source or "rt.NewSizedIntList(" in source)
                if transformed != (variant == "prototype"):
                    continue
                if (transformed and args.build_type == "Debug" and
                        "Items: append([]rt.Value(nil), debugLiteralData1[:]...)" not in source):
                    continue
                matches.append(file)
            original = max(matches, key=lambda file: file.stat().st_mtime_ns)
            source = original.read_text()
            # The emitter creates values() as its first source function.
            symbols = re.findall(r"(?m)^\t(\w+) = func\(\) rt.Function \{", source)
            symbol = symbols[1] if args.elements == "calls" else symbols[0]
            directory = root / str(n) / variant
            directory.mkdir(exist_ok=True)
            (directory / "main.go").write_text(source)
            (directory / "provenance.json").write_text(json.dumps(dict(
                cache_source=str(original), source_sha256=hashlib.sha256(source.encode()).hexdigest(),
                elements=n, variant=variant, symbol=symbol,
            ), indent=2) + "\n")
            expected = "int64(7)" if args.elements == "calls" else "i"
            first_value = 7 if args.elements == "calls" else 0
            harness = f'''package main
import("testing"; rt "github.com/manuscript-lang/manuscript/pkg/runtime")
var sink rt.Value
func TestResult(t *testing.T) {{
 initialize()
 ctx:=rt.RootExecution()
 defer rt.FinishExecution(ctx)
 first:=rt.Invoke(ctx,{symbol},nil)
 second:=rt.Invoke(ctx,{symbol},nil)
 if rt.IntValue(rt.CollectionLength(ctx,first))!={n} || rt.IntValue(rt.CollectionLength(ctx,second))!={n} {{t.Fatal("length")}}
 at:=func(list rt.Value,index int64) int64 {{return rt.IntValue(rt.OptionalUnwrap(ctx,rt.ListAt(ctx,list,index,"@std/Optional[Int]")))}}
 for i:=int64(0);i<{n};i++ {{if v:=at(first,i);v!={expected} {{t.Fatal(i,v)}}}}
 rt.Invoke(ctx,rt.NativeMemberResult(first,"set","@std/List[Int]"),[]rt.Argument{{{{Name:"index",Value:int64(0)}},{{Name:"value",Value:int64({n}-1)}}}})
 if at(first,0)!={n}-1 || at(second,0)!={first_value} {{t.Fatal("shared storage or lost mutation")}}
}}
func BenchmarkLiteral(b *testing.B) {{
 initialize();ctx:=rt.RootExecution();defer rt.FinishExecution(ctx);b.ReportAllocs();b.ResetTimer()
 for i:=0;i<b.N;i++ {{sink=rt.Invoke(ctx,{symbol},nil)}}
}}
'''
            (directory / "program_test.go").write_text(harness)
            with (directory / "test-build.log").open("w") as log:
                flags = (["-gcflags=all=-N -l", "-ldflags=-compressdwarf=false"]
                         if args.build_type == "Debug" else [])
                subprocess.run([args.go, "test", "-mod=vendor", "-tags=ms_lean", *flags,
                                "-c", "-o", str(directory / "runtime.test"),
                                str(directory / "main.go"), str(directory / "program_test.go")],
                               cwd=args.repo, stdout=log, stderr=log, check=True)
            print(n, variant, original, flush=True)


if __name__ == "__main__":
    main()
