#!/usr/bin/env python3
"""Validate exact trees, then measure balanced, interleaved compiler samples."""
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
    parser.add_argument("out", type=Path)
    parser.add_argument("--baseline-revision", required=True)
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--suite", choices=["suffix", "speculation"], default="suffix")
    args = parser.parse_args()
    assert args.samples >= 6 and args.samples % 2 == 0
    args.out.mkdir(parents=True, exist_ok=False)
    inputs = args.out / "inputs"
    inputs.mkdir()
    repo = Path(__file__).resolve().parents[3]
    cases = {}

    def source(name, text):
        path = inputs / f"{name}.ms"
        path.write_bytes(text.encode())
        cases[name] = [path]

    def functions(result, count=16):
        return "".join(f"fn f{i}(value: Int) {result}:\n    return value\n" for i in range(count))

    source("tiny", functions("Int", 1))
    source("plain-256", functions("Int", 256))
    source("single-optional-256", functions("Int?", 256))
    source("single-result-256", functions("Int!", 256))
    source("generic-optional-256", functions("List[Map[String, List[Int]]]?", 256))
    for depth in [16, 64, 128, 256, 512]:
        source(f"optional-{depth}", functions("Int" + "?" * depth))
    for depth in [64, 128, 256]:
        source(f"result-{depth}", functions("Int" + "!" * depth))
    source("mixed-128-crlf", functions("Int" + "?!E" * 64).replace("\n", "\r\n"))
    cases["stdlib"] = sorted((repo / "stdlib").glob("*.ms"))
    if args.suite == "speculation":
        cases.clear()
        source("tiny", functions("Int", 1))
        source("plain-256", functions("Int", 256))
        source("generic-optional-256", functions("List[Map[String, List[Int]]]?", 256))
        for depth in [1, 2, 4, 8, 16, 64, 128, 256]:
            source(f"index-{depth}", "fn f(data: List[Int]) Int:\n    return " + "data[" * depth + "0" + "]" * depth + "\n")
        for label, expression in [("flat-name", "data[index]"), ("flat-value", "data[index + 1]")]:
            source(label, "fn f(data: List[Int], index: Int) Int:\n    return " + expression + "\n")
        source("mixed-flat-after-nested", "fn f(data: List[Int], index: Int) List[Int]:\n    return [" + "data[" * 16 + "0" + "]" * 16 + "," + ",".join(["data[index + 1]"] * 256) + "]\n")
        for depth in [16, 32, 64]:
            ty = "List[" * depth + "Int" + "]" * depth
            source(f"nested-type-{depth}", functions(ty))
            source(f"generic-apply-{depth}", "fn f() Int:\n    return value[" + ty + "]\n")
        cases["stdlib"] = sorted((repo / "stdlib").glob("*.ms"))
    binaries = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    if affinity:
        os.sched_setaffinity(0, {affinity[0]})

    def run(which, mode, paths):
        return subprocess.check_output([str(binaries[which]), mode, *map(str, paths)])

    evidence = {
        "platform": platform.platform(), "cpu_affinity": affinity[:1],
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
        "baseline_revision": args.baseline_revision,
        "baseline_parser_sha256": digest(subprocess.check_output(
            ["git", "show", f"{args.baseline_revision}:crates/ms-syntax/src/parser.rs"], cwd=repo)),
        "rustc": subprocess.check_output(["rustc", "-vV"], text=True),
        "binaries": {key: digest(path.read_bytes()) for key, path in binaries.items()},
        "parser_sha256": digest((repo / "crates/ms-syntax/src/parser.rs").read_bytes()),
        "validation": {}, "samples": [],
    }
    if args.suite == "speculation":
        evidence["outcome_parity"] = []
        for depth in [1, 2, 4, 16, 64, 256, 990, 999, 1000, 1001]:
            for atom in ["0", "index", "index + 1", "Box[Int]", "Box[Int, 0]", "fn(Int) Int", "fn(Int) ", "(fn(Int) Int)?", "Int!E", "List[Int", "(index + 1)"]:
                text = "fn f(data: List[Int]) Int:\n    return " + "data[" * depth + atom + "]" * depth + "\n"
                for ending in ["\n", "\r\n"]:
                    path = inputs / "outcome.src"
                    path.write_bytes(text.replace("\n", ending).encode())
                    before = run("baseline", "outcome", [path])
                    assert before == run("candidate", "outcome", [path]), (depth, atom, ending)
                    evidence["outcome_parity"].append({"depth": depth, "atom": atom, "ending": repr(ending), "sha256": digest(before)})
        evidence["recovery_parity"] = []
        for depth in [2, 16, 64]:
            text = "fn broken(\nfn f(data: List[Int]) Int:\n    return " + "data[" * depth + "0" + "]" * depth + "\n"
            for ending in ["\n", "\r\n"]:
                path = inputs / "recovery.src"
                path.write_bytes(text.replace("\n", ending).encode())
                before = run("baseline", "partial", [path])
                assert before == run("candidate", "partial", [path]), (depth, ending)
                evidence["recovery_parity"].append({"depth": depth, "ending": repr(ending), "sha256": digest(before)})
    for name, paths in cases.items():
        before = run("baseline", "validate", paths)
        after = run("candidate", "validate", paths)
        assert before == after, f"tree, IDs, positions, source or dump changed: {name}"
        evidence["validation"][name] = {
            "tree_sha256": digest(before),
            "inputs": [{"path": str(path.relative_to(repo)) if path.is_relative_to(repo) else path.name,
                        "sha256": digest(path.read_bytes()), "bytes": path.stat().st_size} for path in paths],
        }
    randomizer = random.Random(1729)
    for trial in range(args.samples):
        names = list(cases)
        randomizer.shuffle(names)
        order = ["baseline", "candidate"] if trial % 2 == 0 else ["candidate", "baseline"]
        for name in names:
            for which in order:
                row = json.loads(run(which, "parse", cases[name]))
                assert row["checksum"] == row["units"] * row["passes"]
                row.update(case=name, which=which, trial=trial)
                evidence["samples"].append(row)
                (args.out / "results.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("case baseline_us candidate_us speedup paired_central_order_statistics")
    for name in cases:
        values = {}
        for which in binaries:
            values[which] = [r["elapsed_ns"] / r["passes"] for r in evidence["samples"]
                             if r["case"] == name and r["which"] == which]
        paired = sorted(a / b for a, b in zip(values["baseline"], values["candidate"]))
        before, after = (statistics.median(values[key]) for key in binaries)
        print(f"{name} {before / 1000:.3f} {after / 1000:.3f} {before / after:.3f} "
              f"{paired[len(paired) // 10]:.3f}..{paired[-1 - len(paired) // 10]:.3f}")


if __name__ == "__main__":
    main()
