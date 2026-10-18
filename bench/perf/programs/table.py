"""Validate equivalent work before comparing paired process samples."""

import statistics
import sys
from collections import defaultdict

OPS = {
    "string_append_50k": 50_000,
    "read_line": 200_000,
    "map_put_get_8k": 16_000,
    "int_eq": 10_000_000,
    "generic_call": 1_000_000,
    "method_call": 1_000_000,
    "try": 1_000_000,
    "match": 1_000_000,
    "builtin_length": 1_000_000,
    "for_list": 1_000_000,
}
SINK = [50_000, 63_992_000, 3_333_334, 499_999_500_000, 1_000_000,
        500_000_500_000, 6_333_333, 100_000_000, 499_999_500_000]


def summarize(lines, repeats):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    samples = defaultdict(list)
    pending = defaultdict(set)
    sinks = defaultdict(int)
    for line in lines:
        parts = line.split()
        if len(parts) < 2 or parts[0] not in ("ms", "go"):
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
    for version in ("ms", "go"):
        if pending[version] or sinks[version] != repeats:
            raise ValueError(f"expected {repeats} complete {version} samples")
    rows = []
    for name, count in OPS.items():
        ms = statistics.median(samples["ms", name])
        go = statistics.median(samples["go", name])
        rows.append(f"| {name} | {count} | {ms:,.2f} | {go:,.2f} | {ms/go:,.2f}x |")
    return (f"Median of {repeats} alternating runs; ns/op. Checksums and operation counts verified.\n\n"
            "| operation | ops | Manuscript | Go | ratio |\n"
            "|---|---:|---:|---:|---:|\n" + "\n".join(rows))


if __name__ == "__main__":
    try:
        with open(sys.argv[1]) as raw:
            print(summarize(raw, int(sys.argv[2])))
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
