"""Compare two `ms` builds on the bench/perf/stdlib bench blocks, alternating runs and checking the cases match."""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess

SUITE = Path(__file__).resolve().parent / "stdlib"


def parse_sample(output, expected=None):
    """Reads one `ms bench --json` document: ({case: (operations, median ns/op)}, {case: operations})."""
    document = json.loads(output)
    if document.get("diagnostics"):
        raise ValueError("; ".join(d["message"] for d in document["diagnostics"]))
    rows = {}
    for case in document["benches"]:
        name = case["name"].split("::", 1)[-1]
        if name in rows:
            raise ValueError(f"duplicate case: {name}")
        if case["status"] != "passed":
            raise ValueError(f"{name}: {case['status']}: {case.get('failure', '')}")
        stats = case["stats"]
        if stats["operations"] <= 0 or stats["median_ns"] < 0:
            raise ValueError(f"invalid measurement: {name}")
        rows[name] = (stats["operations"], stats["median_ns"])
    if not rows:
        raise ValueError("no cases were measured")
    identity = {name: operations for name, (operations, _) in rows.items()}
    if expected is not None and identity != expected:
        raise ValueError("cases or operation counts changed")
    return rows, identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("before", "after", "output"):
        parser.add_argument("--" + name, type=Path, required=True, help="ms binary" if name != "output" else "directory")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--samples", type=int, default=5, help="timed samples per case in each run")
    parser.add_argument("--filter", default="", help="only cases whose module::name contains this text")
    args = parser.parse_args()
    if args.repeats < 1 or args.samples < 1:
        parser.error("repeats and samples must be positive")
    binaries = {name: getattr(args, name).resolve() for name in ("before", "after")}
    raw = {name: [] for name in binaries}
    samples = {name: {} for name in binaries}
    expected = None
    for iteration in range(args.repeats):
        order = ("before", "after") if iteration % 2 == 0 else ("after", "before")
        for version in order:
            command = [str(binaries[version]), "bench", "ms.toml", "--json", "--samples", str(args.samples)]
            if args.filter:
                command += ["--filter", args.filter]
            result = subprocess.run(command, cwd=SUITE, capture_output=True, text=True, check=False)
            rows, identity = parse_sample(result.stdout, expected)
            if expected is None:
                expected = identity
            raw[version].append(result.stdout)
            for name, (_, value) in rows.items():
                samples[version].setdefault(name, []).append(value)
    args.output.mkdir(parents=True, exist_ok=True)
    summary = {}
    table = [f"Median of {args.repeats} alternating runs of {args.samples} samples; all {len(expected)} cases and operation counts verified.", "",
             "| operation | ops | before ns/op | after ns/op | after/before |",
             "|---|---:|---:|---:|---:|"]
    for name, ops in expected.items():
        before = statistics.median(samples["before"][name])
        after = statistics.median(samples["after"][name])
        ratio = after / before if before else None
        summary[name] = {"ops": ops, "before": before, "after": after, "ratio": ratio}
        ratio_text = f"{ratio:.3f}x" if ratio is not None else "—"
        table.append(f"| {name} | {ops} | {before:.4g} | {after:.4g} | {ratio_text} |")
    for version, outputs in raw.items():
        (args.output / f"stdlib-{version}.jsonl").write_text("".join(o.strip() + "\n" for o in outputs))
    metadata = {"platform": platform.platform(), "repeats": args.repeats, "samples": args.samples,
                "binaries": {name: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                             for name, path in binaries.items()}}
    (args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    rendered = "\n".join(table) + "\n"
    (args.output / "results.md").write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
