"""Reads the `ms bench --json` document on stdin and prints the median, min, and max ns per operation of each case."""
import sys

from stdlib_results import case_labels, read_cases

try:
    cases = read_cases(sys.stdin.read())
except (ValueError, KeyError, TypeError) as error:
    sys.exit(str(error))
labels = case_labels(cases)
rows = [(labels[name], case["stats"]["median_ns"], case["stats"]["min_ns"], case["stats"]["max_ns"])
        for name, case in cases.items()]
width = max((len(r[0]) for r in rows), default=4)
print(f"{'case':<{width}}  {'median ns/op':>12}  {'min':>10}  {'max':>10}")
for name, median, low, high in rows:
    print(f"{name:<{width}}  {median:>12.2f}  {low:>10.2f}  {high:>10.2f}")
