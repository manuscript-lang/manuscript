"""Validate complete trials before printing per-kernel minimum microseconds.

Rows are `<version> <kernel> <microseconds> <checksum>`. Each successful
producer ends its trial with `<version> # end`. Times below two microseconds
are reported as folded rather than used in ratios.
"""
import sys
from collections import defaultdict

SUITES = {
    "kernels": ("sieve_5M", "nbody_200k", "life_128x128_50", "matmul_200",
                "trees_d16_x20", "collatz_1M", "map_count_2M"),
    "competence": ("call_fib_36", "dispatch_100M", "closure_100M", "sort_1M",
                   "text_1M", "strmap_10M", "errors_50M", "records_1M_x20",
                   "grid2d_500x20", "struct_100M", "stack_20M", "optional_100M",
                   "set_2M", "chars_1M"),
}
VERSIONS = ("go", "ms", "rust", "rust-checked")
C_VERSIONS = ("c", "c-ms")
ABLATIONS = ("c-ms-no-poll", "c-ms-no-overflow", "c-ms-no-bounds", "c-ms-unchecked")


def ratio(num, den):
    return "folded" if min(num, den) < 2 else f"{num / den:.2f}x"


def summarize(lines, suite, repeats, versions):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    allowed = [VERSIONS]
    if suite == "kernels":
        allowed = [VERSIONS + C_VERSIONS, VERSIONS + C_VERSIONS + ABLATIONS]
    if tuple(versions) not in allowed:
        raise ValueError(f"unexpected versions for {suite}: {versions}")
    names = SUITES[suite]
    samples = defaultdict(list)
    checks = defaultdict(set)
    trials = dict.fromkeys(versions, 0)
    pending = set()
    active = None
    for line in lines:
        parts = line.split()
        if len(parts) < 2 or parts[0] not in versions:
            raise ValueError(f"invalid sample: {line.rstrip()}")
        version, name = parts[:2]
        if active is not None and version != active:
            raise ValueError(f"unterminated {active} trial")
        active = version
        if parts[1:] == ["#", "end"]:
            if pending != set(names):
                raise ValueError(f"incomplete {version} trial")
            trials[version] += 1
            pending.clear()
            active = None
            continue
        if len(parts) != 4 or name not in names or name in pending:
            raise ValueError(f"invalid kernel: {line.rstrip()}")
        micros, check = map(int, parts[2:])
        if micros < 0:
            raise ValueError(f"negative timing: {line.rstrip()}")
        samples[name, version].append(micros)
        checks[name].add(check)
        pending.add(name)
    if active is not None or any(count != repeats for count in trials.values()):
        raise ValueError(f"expected {repeats} complete trials of every version")
    for name in names:
        if len(checks[name]) != 1:
            raise ValueError(f"{name}: checksums differ between runs or versions")

    others = [v for v in versions if v != "go"]
    extra = ["ms / " + v for v in others if v.startswith("rust")]
    rows = [
        f"Minimum of {repeats} rotating runs; microseconds. Complete trials and checksums verified.\n",
        "| kernel | go us | " + " | ".join(f"{v} us | {v} / go" for v in others) + " | " + " | ".join(extra) + " |",
        "|---|---:|" + "---:|---:|" * len(others) + "---:|" * len(extra),
    ]
    for name in names:
        times = {v: min(samples[name, v]) for v in versions}
        cells = [f"{times[v]} | {ratio(times[v], times['go'])}" for v in others]
        tail = [ratio(times["ms"], times[v]) for v in others if v.startswith("rust")]
        rows.append(f"| {name} | {times['go']} | " + " | ".join(cells + tail) + " |")
    return "\n".join(rows)


if __name__ == "__main__":
    try:
        with open(sys.argv[1]) as raw:
            print(summarize(raw, sys.argv[2], int(sys.argv[3]), tuple(sys.argv[4].split())))
    except (ValueError, IndexError, KeyError) as error:
        sys.exit(str(error))
