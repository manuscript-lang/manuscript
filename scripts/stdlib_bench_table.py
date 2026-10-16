"""Reads `name<TAB>ops<TAB>ns_per_op` lines on stdin and prints the median/min/max ns per op per case."""
import statistics
import sys

prefix = sys.argv[1] if len(sys.argv) > 1 else ""
rows = {}
for line in sys.stdin:
    name, _ops, ns = line.rstrip("\n").split("\t")
    if name.startswith(prefix):
        rows.setdefault(name, []).append(int(ns))
width = max((len(n) for n in rows), default=4)
print(f"{'case':<{width}}  {'median ns/op':>12}  {'min':>8}  {'max':>8}")
for name, vals in rows.items():
    print(f"{name:<{width}}  {int(statistics.median(vals)):>12}  {min(vals):>8}  {max(vals):>8}")
