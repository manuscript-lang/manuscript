"""Reads the `ms bench --json` document on stdin and prints the median, min, and max ns per operation of each case."""
import json
import sys

document = json.load(sys.stdin)
if document.get("diagnostics"):
    sys.exit("\n".join(d["message"] for d in document["diagnostics"]))
if not document["benches"]:
    sys.exit("no cases were measured")
rows = []
for case in document["benches"]:
    name = case["name"].split("::", 1)[-1]
    if case["status"] != "passed":
        sys.exit(f"{name}: {case['status']}: {case.get('failure', '')}")
    stats = case["stats"]
    rows.append((name, stats["median_ns"], stats["min_ns"], stats["max_ns"]))
width = max((len(r[0]) for r in rows), default=4)
print(f"{'case':<{width}}  {'median ns/op':>12}  {'min':>10}  {'max':>10}")
for name, median, low, high in rows:
    print(f"{name:<{width}}  {median:>12.2f}  {low:>10.2f}  {high:>10.2f}")
