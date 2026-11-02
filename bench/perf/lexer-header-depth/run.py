#!/usr/bin/env python3
"""Validate exact syntax/lexical output, then interleave pinned compiler samples."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("baseline_tokens", type=Path)
    parser.add_argument("candidate_tokens", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--baseline-revision", required=True)
    parser.add_argument("--samples", type=int, default=10)
    args = parser.parse_args()
    assert args.samples >= 6 and args.samples % 2 == 0
    args.out.mkdir(parents=True, exist_ok=False)
    inputs = args.out / "inputs"
    inputs.mkdir()
    repo = Path(__file__).resolve().parents[3]
    cases = {}

    def source(name, text):
        path = inputs / (name + ".ms")
        path.write_bytes(text.encode())
        cases[name] = [path]

    source("tiny", "fn f() Int:\n    return 1\n")
    for size in [1024, 1048576]:
        source(f"comment-{size}", "#" + "a" * size + "\n")
        source(f"text-{size}", 'let text = "' + "a" * size + '"\n')
    for count in [256, 4096]:
        source(f"declarations-{count}", "".join(
            f"fn f{i}(x: Int) Int:\n    return x + {i}\n" for i in range(count)))
        source(f"body-{count}", "fn f() Int:\n" + "".join(
            f"    let x{i} = {i} + 1\n" for i in range(count)) + "    return 0\n")
    for count in [256, 32768]:
        source(f"dense-{count}", "let values = [" + ",".join(["0"] * count) + "]\n")
    declarations = cases["declarations-256"][0].read_text()
    source("crlf", declarations.replace("\n", "\r\n"))
    for depth in [1, 16, 64, 128, 256, 512]:
        text = ("fn f(value:\n" + "    fn(\n" * depth + "        Int\n" +
                "    ) Unit\n" * depth + ") Unit:\n    return unit\n")
        source(f"function-{depth}-lf", text)
        if depth >= 64:
            source(f"function-{depth}-crlf", text.replace("\n", "\r\n"))
    headers = (Path(__file__).resolve().parent / "delimited-header-depths.src").read_text()
    source("delimited-headers-lf", headers)
    source("delimited-headers-crlf", headers.replace("\n", "\r\n"))
    cases["stdlib"] = sorted((repo / "stdlib").glob("*.ms"))
    binaries = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    tokens = {"baseline": args.baseline_tokens.resolve(), "candidate": args.candidate_tokens.resolve()}
    if hasattr(os, "sched_getaffinity"):
        os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
    evidence = {
        "platform": platform.platform(), "affinity": sorted(os.sched_getaffinity(0)),
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
        "baseline_revision": args.baseline_revision,
        "lexer_sha256": digest((repo / "crates/ms-syntax/src/lexer.rs").read_bytes()),
        "baseline_lexer_sha256": digest(subprocess.check_output([
            "git", "show", args.baseline_revision + ":crates/ms-syntax/src/lexer.rs"], cwd=repo)),
        "rustc": subprocess.check_output(["rustc", "-vV"], text=True),
        "binaries": {key: digest(path.read_bytes()) for key, path in binaries.items()},
        "token_binaries": {key: digest(path.read_bytes()) for key, path in tokens.items()},
        "validation": {}, "samples": [],
    }

    def run(which, mode, paths):
        return subprocess.check_output([str(binaries[which]), mode, *map(str, paths)])

    for name, paths in cases.items():
        tree = run("baseline", "validate", paths)
        assert tree == run("candidate", "validate", paths), (name, "tree")
        lexical = subprocess.check_output([str(tokens["baseline"]), *map(str, paths)])
        assert lexical == subprocess.check_output([str(tokens["candidate"]), *map(str, paths)]), (name, "tokens")
        evidence["validation"][name] = {
            "tree_sha256": digest(tree), "tokens_sha256": digest(lexical),
            "inputs": [{"name": path.name, "bytes": path.stat().st_size,
                        "sha256": digest(path.read_bytes())} for path in paths],
        }
    rng = random.Random(1729)
    for trial in range(args.samples):
        work = [(name, mode) for name in cases for mode in ["lex", "parse"]]
        rng.shuffle(work)
        order = ["baseline", "candidate"] if trial % 2 == 0 else ["candidate", "baseline"]
        for name, mode in work:
            for which in order:
                row = json.loads(run(which, mode, cases[name]))
                assert row["checksum"] == row["units"] * row["passes"]
                row.update(case=name, mode=mode, which=which, trial=trial)
                evidence["samples"].append(row)
                (args.out / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("mode case baseline_us candidate_us speedup paired_central_order_statistics")
    for mode in ["lex", "parse"]:
        for name in cases:
            values = {}
            for which in binaries:
                values[which] = [row["elapsed_ns"] / row["passes"] for row in evidence["samples"]
                                 if row["case"] == name and row["mode"] == mode and row["which"] == which]
            ratios = sorted(a / b for a, b in zip(values["baseline"], values["candidate"]))
            before, after = (statistics.median(values[key]) for key in binaries)
            print(f"{mode} {name} {before / 1000:.3f} {after / 1000:.3f} {before / after:.3f} "
                  f"{ratios[len(ratios) // 10]:.3f}..{ratios[-1 - len(ratios) // 10]:.3f}")


if __name__ == "__main__":
    main()
