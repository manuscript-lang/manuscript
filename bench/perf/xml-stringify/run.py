#!/usr/bin/env python3
"""Compare two XML modules at identical import paths with complete output checks."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ms", type=Path, default=Path("target/release/ms"))
    parser.add_argument("--before", default="2050d2b4f56bc9851cb58c17f6eabb125610e7a2")
    parser.add_argument("--pairs", type=int, default=15)
    parser.add_argument("--cpu", type=int, default=0)
    parser.add_argument("--output", type=Path, default=Path(".artifacts/xml-stringify"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    compiler = args.ms.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    probe = output / "main.ms"
    probe.write_text(Path(__file__).with_name("probe.ms").read_text().replace(
        '"@std/data/xml.ms"', '"./xml.ms"'
    ))
    modules = {
        "before": subprocess.check_output(
            ["git", "show", f"{args.before}:stdlib/data/xml.ms"], cwd=root
        ),
        "after": (root / "stdlib/data/xml.ms").read_bytes(),
    }
    env = dict(os.environ, MS_BACKEND="cranelift", MS_CACHE="off")
    for variant, source in modules.items():
        (output / "xml.ms").write_bytes(source)
        subprocess.run([
            str(compiler), "build", str(probe), "--build-type", "Release", "-o",
            str(output / variant),
        ], env=env, check=True)
    rows = []
    for pair in range(args.pairs):
        order = ["before", "after"] if pair % 2 == 0 else ["after", "before"]
        for variant in order:
            prior = resource.getrusage(resource.RUSAGE_CHILDREN)
            text = subprocess.check_output([
                "taskset", "-c", str(args.cpu), str(output / variant)
            ], text=True)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            for case, operations, ns, checksum in csv.reader(text.splitlines()):
                rows.append(dict(
                    pair=pair, variant=variant, case=case, operations=int(operations),
                    ns=int(ns), checksum=int(checksum),
                    minor_faults=after.ru_minflt - prior.ru_minflt,
                    major_faults=after.ru_majflt - prior.ru_majflt,
                ))
    assert len(rows) == args.pairs * 2 * 19, "incomplete benchmark output"
    for case in dict.fromkeys(row["case"] for row in rows):
        checksums = {row["checksum"] for row in rows if row["case"] == case}
        assert len(checksums) == 1, f"checksum mismatch: {case}"
    with (output / "samples.csv").open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0])
        writer.writeheader()
        writer.writerows(rows)
    summary = []
    for case in dict.fromkeys(row["case"] for row in rows):
        before, after = [statistics.median([
            row["ns"] / row["operations"] for row in rows
            if row["case"] == case and row["variant"] == variant
        ]) for variant in ["before", "after"]]
        summary.append(dict(case=case, before_ns=round(before, 2),
                            after_ns=round(after, 2), ratio=round(after / before, 4)))
    with (output / "summary.csv").open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=summary[0])
        writer.writeheader()
        writer.writerows(summary)
    metadata = dict(
        before_ref=args.before, platform=platform.platform(), cpu=args.cpu,
        compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
        probe_sha256=hashlib.sha256(probe.read_bytes()).hexdigest(),
        module_sha256={k: hashlib.sha256(v).hexdigest() for k, v in modules.items()},
    )
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
