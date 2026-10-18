"""Compare two built library benchmark revisions, checking every checksum."""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess


def parse_sample(output, expected=None, case_count=66, require_elapsed=False):
    rows, checksums, elapsed = {}, {}, {}
    for line in output.splitlines():
        if line.startswith("# checksum "):
            name, value = line.removeprefix("# checksum ").split()
            if name in checksums:
                raise ValueError(f"duplicate checksum: {name}")
            checksums[name] = int(value)
        elif line.startswith("# elapsed "):
            name, value = line.removeprefix("# elapsed ").split()
            if name in elapsed or int(value) < 0:
                raise ValueError(f"invalid elapsed time: {line}")
            elapsed[name] = int(value)
        elif line and not line.startswith("#"):
            name, count, ns = line.split("\t")
            if name in rows:
                raise ValueError(f"duplicate operation: {name}")
            count, ns = int(count), int(ns)
            if count <= 0 or ns < 0:
                raise ValueError(f"invalid measurement: {line}")
            rows[name] = (count, ns)
    if len(rows) != case_count or rows.keys() != checksums.keys():
        raise ValueError("incomplete operations/checksums")
    if elapsed or require_elapsed:
        if elapsed.keys() != rows.keys():
            raise ValueError("incomplete elapsed times")
        for name, (count, rounded) in rows.items():
            if rounded != elapsed[name] // count:
                raise ValueError(f"elapsed time disagrees with rounded row: {name}")
        rows = {name: (count, elapsed[name] / count) for name, (count, _) in rows.items()}
    identity = {name: (count, checksums[name]) for name, (count, _) in rows.items()}
    if expected is not None and identity != expected:
        raise ValueError("operation counts or checksums changed")
    return rows, identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("before", "after", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=30)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("repeats must be positive")
    binaries = {name: getattr(args, name).resolve() for name in ("before", "after")}
    raw = {name: [] for name in binaries}
    samples = {name: {} for name in binaries}
    expected = None
    for iteration in range(args.repeats):
        order = ("before", "after") if iteration % 2 == 0 else ("after", "before")
        for version in order:
            result = subprocess.run([str(binaries[version])], capture_output=True, text=True, check=True, timeout=120)
            rows, identity = parse_sample(result.stdout, expected, require_elapsed=True)
            if expected is None:
                expected = identity
            raw[version].append(result.stdout)
            for name, (_, value) in rows.items():
                samples[version].setdefault(name, []).append(value)
    args.output.mkdir(parents=True, exist_ok=True)
    summary = {}
    table = [f"Median of {args.repeats} alternating runs; all 66 counts and checksums verified.", "",
             "| operation | ops | before ns/op | after ns/op | after/before |",
             "|---|---:|---:|---:|---:|"]
    for name, (ops, checksum) in expected.items():
        before = statistics.median(samples["before"][name])
        after = statistics.median(samples["after"][name])
        ratio = after / before if before else None
        summary[name] = {"ops": ops, "checksum": checksum, "before": before, "after": after, "ratio": ratio}
        ratio_text = f"{ratio:.3f}x" if ratio is not None else "—"
        table.append(f"| {name} | {ops} | {before:g} | {after:g} | {ratio_text} |")
    for version, outputs in raw.items():
        (args.output / f"stdlib-{version}.txt").write_text("".join(outputs))
    metadata = {"platform": platform.platform(), "repeats": args.repeats,
                "binaries": {name: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                             for name, path in binaries.items()}}
    (args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    rendered = "\n".join(table) + "\n"
    (args.output / "results.md").write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
