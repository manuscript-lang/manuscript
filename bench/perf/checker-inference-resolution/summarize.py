"""Print every retained comparison; ratios pair the same numbered round."""
import collections
import argparse
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser()
parser.add_argument("results", type=Path, help="Directory containing local measurement JSON")
root = parser.parse_args().results
for path in sorted(root.rglob("*.json")):
    data = json.loads(path.read_text())
    if "samples" not in data:
        continue
    cases = collections.defaultdict(dict)
    for sample in data["samples"]:
        if sample["round"] < 0:
            continue
        if "measurement" in sample:
            m = sample["measurement"]
            case, value = m["case"], m["elapsed_ns"] / m["iterations"]
        else:
            case, value = sample["case"], sample["wall_ns"]
            if "condition" in sample:
                case += "/" + sample["condition"]
        cases[case][sample["round"], sample["label"]] = value
    print(f"\n{path.relative_to(root)} (nanoseconds per operation/process)")
    for case, values in sorted(cases.items()):
        labels = sorted({label for _, label in values})
        medians = {label: statistics.median(v for (_, l), v in values.items() if l == label) for label in labels}
        detail = " ".join(f"{label}={v:.3f}" for label, v in medians.items())
        if len(labels) == 2:
            before, after = labels
            ratios = [values[r, after] / values[r, before] for r, l in values if l == before]
            detail += f" paired={statistics.median(ratios):.6f} slower={sum(r > 1 for r in ratios)}/{len(ratios)}"
        print(f"{case}: {detail}")
