"""Print per-kernel minimum microseconds for Go and Manuscript, and their ratio.

Input lines are `<lang> <kernel> <microseconds> <checksum>`. Every sample of a
kernel must report the same checksum in both languages.
"""
import sys

best, checks = {}, {}
for line in open(sys.argv[1]):
    lang, name, micros, check = line.split()
    best.setdefault(name, {})
    best[name][lang] = min(best[name].get(lang, float("inf")), int(micros))
    checks.setdefault(name, set()).add(check)

print("| kernel | Go us | Manuscript us | Manuscript / Go |")
print("|---|---:|---:|---:|")
for name, langs in best.items():
    if len(checks[name]) != 1:
        sys.exit(f"{name}: checksums differ between runs or languages: {sorted(checks[name])}")
    print(f"| {name} | {langs['go']} | {langs['ms']} | {langs['ms'] / langs['go']:.2f}x |")
