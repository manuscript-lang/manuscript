"""Validate complete data-structure trials before comparing minimum ns/op.

Samples are `<version> <operation> <count> <nanoseconds>`. The runner appends
`<version> # end` only after a successful producer. Producers do not emit checksums.
"""
import sys

OPERATIONS = {
    "list_append": 1_000_000,
    "list_get_random": 1_000_000,
    "list_sort_int": 1_000_000,
    "list_sort_cmp": 300_000,
    "map_int_put_get": 2_000_000,
    "map_str_put_get": 400_000,
    "set_int_add_contains": 2_000_000,
    "string_build_split_join_replace": 200_000,
    "bytes_append": 4_000_000,
    "pq_int_enqueue_dequeue": 600_000,
    "sorted_map_add_contains": 600_000,
}
VERSIONS = ("ms", "go", "rs")


def operations(version):
    # Go has no sorted-map producer; all other rows are required in every version.
    return set(OPERATIONS) - ({"sorted_map_add_contains"} if version == "go" else set())


def ratio(num, den):
    return "-" if num is None or den is None or min(num, den) == 0 else f"{num / den:.2f}"


def summarize(lines, repeats):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    best = {}
    trials = dict.fromkeys(VERSIONS, 0)
    active = None
    pending = set()
    for line in lines:
        parts = line.split()
        if len(parts) < 2 or parts[0] not in VERSIONS:
            raise ValueError(f"invalid sample: {line.rstrip()}")
        version, name = parts[:2]
        if active is not None and version != active:
            raise ValueError(f"unterminated {active} trial")
        active = version
        if parts[1:] == ["#", "end"]:
            if pending != operations(version):
                raise ValueError(f"incomplete {version} trial")
            trials[version] += 1
            active = None
            pending.clear()
            continue
        if len(parts) != 4 or name not in operations(version) or name in pending:
            raise ValueError(f"invalid operation: {line.rstrip()}")
        ops, ns = map(int, parts[2:])
        if ops != OPERATIONS[name] or ns < 0:
            raise ValueError(f"invalid count or timing: {line.rstrip()}")
        key = (name, version)
        best[key] = min(best.get(key, ns), ns)
        pending.add(name)
    if active is not None or any(count != repeats for count in trials.values()):
        raise ValueError(f"expected {repeats} complete trials of every version")

    rows = [
        f"Minimum of {repeats} rotating trials; ns/op. Complete trials and operation counts verified.",
        "Missing comparisons and zero timings have no ratio. Producers do not report checksums.\n",
        f"{'operation':34}{'ms':>9}{'go':>9}{'rust':>9}{'ms/go':>8}{'ms/rust':>9}",
    ]
    for name, ops in OPERATIONS.items():
        m = best[name, "ms"] / ops
        g = best[name, "go"] / ops if (name, "go") in best else None
        r = best[name, "rs"] / ops
        cells = [f"{value:9.1f}" if value is not None else f"{'-':>9}" for value in (m, g, r)]
        rows.append(f"{name:34}{''.join(cells)}{ratio(m, g):>8}{ratio(m, r):>9}")
    return "\n".join(rows)


if __name__ == "__main__":
    try:
        with open(sys.argv[1]) as raw:
            print(summarize(raw, int(sys.argv[2])))
    except (ValueError, IndexError, OSError) as error:
        sys.exit(str(error))
