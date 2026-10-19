"""Print per-kernel minimum microseconds for each version and its ratio to Go.

Input lines are `<version> <kernel> <microseconds> <checksum>`. Every sample of a
kernel must report the same checksum in every version.
"""
import sys

best, checks, versions = {}, {}, []
for line in open(sys.argv[1]):
    version, name, micros, check = line.split()
    if version not in versions:
        versions.append(version)
    best.setdefault(name, {})
    best[name][version] = min(best[name].get(version, float("inf")), int(micros))
    checks.setdefault(name, set()).add(check)

others = [v for v in versions if v != "go"]
print("| kernel | go us | " + " | ".join(f"{v} us | {v} / go" for v in others) + " |")
print("|---|---:|" + "---:|---:|" * len(others))
for name, times in best.items():
    if len(checks[name]) != 1:
        sys.exit(f"{name}: checksums differ between runs or versions: {sorted(checks[name])}")
    cells = [f"{times[v]} | {times[v] / times['go']:.2f}x" for v in others]
    print(f"| {name} | {times['go']} | " + " | ".join(cells) + " |")
