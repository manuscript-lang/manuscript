"""Validate equivalent work before comparing paired process samples."""

import statistics
import sys
from collections import defaultdict

OPS = {
    "string_append_50k": 50_000,
    "read_line": 200_000,
    "map_put_get_8k": 16_000,
    "int_eq": 10_000_000,
    "generic_call": 100_000_000,
    "method_call": 100_000_000,
    "try": 100_000_000,
    "match": 100_000_000,
    "builtin_length": 100_000_000,
    "for_list": 100_000_000,
}
SINK = [50_000, 63_992_000, 3_333_334, 4_999_999_950_000_000, 100_000_000,
        5_000_000_050_000_000, 633_333_333, 10_000_000_000, 49_999_950_000_000]


VERSIONS = ("ms", "go", "rust", "rust-checked")
TITLES = {"ms": "Manuscript", "go": "Go", "rust": "Rust", "rust-checked": "Rust, overflow checks"}


def summarize(lines, repeats):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    samples = defaultdict(list)
    pending = defaultdict(set)
    sinks = defaultdict(int)
    for line in lines:
        parts = line.split()
        if len(parts) < 2 or parts[0] not in VERSIONS:
            raise ValueError(f"invalid sample: {line.rstrip()}")
        version, name = parts[:2]
        if name == "#":
            if parts[2:3] != ["sink"] or list(map(int, parts[3:])) != SINK:
                raise ValueError(f"incorrect {version} checksum")
            if pending[version] != set(OPS):
                raise ValueError(f"incomplete {version} sample")
            pending[version].clear()
            sinks[version] += 1
            continue
        if len(parts) != 4 or name not in OPS or name in pending[version]:
            raise ValueError(f"invalid operation: {line.rstrip()}")
        count, elapsed = map(int, parts[2:])
        if count != OPS[name] or elapsed <= 0:
            raise ValueError(f"incorrect work count or timing: {line.rstrip()}")
        samples[version, name].append(elapsed / count)
        pending[version].add(name)
    seen = [v for v in VERSIONS if sinks[v] or pending[v]]
    if "ms" not in seen or "go" not in seen:
        raise ValueError("expected ms and go samples")
    for version in seen:
        if pending[version] or sinks[version] != repeats:
            raise ValueError(f"expected {repeats} complete {version} samples")
    others = [v for v in seen if v not in ("ms", "go")]
    rows = []
    for name, count in OPS.items():
        med = {v: statistics.median(samples[v, name]) for v in seen}
        cells = [f"{med[v]:,.2f}" for v in ("ms", "go", *others)]
        cells.append(f"{med['ms'] / med['go']:,.2f}x")
        cells += [f"{med['ms'] / med[v]:,.2f}x" for v in others]
        rows.append(f"| {name} | {count} | " + " | ".join(cells) + " |")
    heads = [TITLES[v] for v in ("ms", "go", *others)] + ["ms / Go"] + [f"ms / {TITLES[v]}" for v in others]
    return (f"Median of {repeats} alternating runs; ns/op. Checksums and operation counts verified.\n\n"
            "| operation | ops | " + " | ".join(heads) + " |\n"
            "|---|---:|" + "---:|" * len(heads) + "\n" + "\n".join(rows))


if __name__ == "__main__":
    try:
        with open(sys.argv[1]) as raw:
            print(summarize(raw, int(sys.argv[2])))
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
