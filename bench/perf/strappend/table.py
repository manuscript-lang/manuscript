"""Validate every string/list sample before reducing to per-case minima."""
import sys

CHECKSUMS = {f"append{size}": 40 * size * (1000000 // size)
             for size in (4, 16, 64, 256, 1024, 8192)}
CHECKSUMS.update({f"list{count}": 40 * count for count in (10000, 100000, 1000000)})


def summarize(lines, repeats):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    seen, best = {}, {}
    for line in lines:
        fields = line.split()
        if len(fields) != 6 or fields[4] != "#":
            raise ValueError(f"invalid sample: {line.rstrip()}")
        trial, version, name, elapsed, _, checksum = fields
        trial, elapsed, checksum = int(trial), int(elapsed), int(checksum)
        if not 0 <= trial < repeats or version not in ("ms", "rust") or name not in CHECKSUMS:
            raise ValueError(f"unknown sample: {line.rstrip()}")
        cases = seen.setdefault((trial, version), set())
        if name in cases or checksum != CHECKSUMS[name] or elapsed <= 0:
            raise ValueError(f"duplicate or invalid measurement: {line.rstrip()}")
        cases.add(name)
        key = name, version
        best[key] = min(best.get(key, elapsed), elapsed)
    if len(seen) != repeats * 2 or any(cases != set(CHECKSUMS) for cases in seen.values()):
        raise ValueError("missing benchmark samples")
    rows = [f"{'size':<12} {'ms_us':>10} {'rust_us':>10} {'ratio':>8}"]
    for name in sorted(CHECKSUMS):
        ms, rust = best[name, "ms"], best[name, "rust"]
        rows.append(f"{name:<12} {ms:>10d} {rust:>10d} {ms / rust:>7.2f}x")
    return "\n".join(rows)


if __name__ == "__main__":
    try:
        with open(sys.argv[1]) as raw:
            print(summarize(raw, int(sys.argv[2])))
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
