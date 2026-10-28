"""Validate the shared ms bench result protocol before rendering comparisons."""
from collections import Counter
import json
import math


def reject_constant(value):
    raise ValueError(f"invalid JSON number: {value}")


def read_cases(output):
    document = json.loads(output, parse_constant=reject_constant)
    if document.get("diagnostics"):
        raise ValueError("; ".join(d["message"] for d in document["diagnostics"]))
    cases = {}
    for case in document["benches"]:
        name = case["name"]
        if name in cases:
            raise ValueError(f"duplicate case: {name}")
        if case["status"] != "passed":
            raise ValueError(f"{name}: {case['status']}: {case.get('failure', '')}")
        stats = case["stats"]
        for field in ("operations", "iterations", "samples"):
            if field == "operations" or field in stats:
                value = stats[field]
                if type(value) is not int or value <= 0:
                    raise ValueError(f"invalid {field}: {name}")
        for field in ("median_ns", "min_ns", "max_ns", "mean_ns", "stddev_ns"):
            if field == "median_ns" or field in stats:
                value = stats[field]
                try:
                    valid = type(value) in (int, float) and math.isfinite(value) and value >= 0
                except OverflowError:
                    valid = False
                if not valid:
                    raise ValueError(f"invalid {field}: {name}")
        if "min_ns" in stats and "max_ns" in stats:
            if not stats["min_ns"] <= stats["median_ns"] <= stats["max_ns"]:
                raise ValueError(f"inconsistent timing range: {name}")
        cases[name] = case
    if not cases:
        raise ValueError("no cases were measured")
    return cases


def case_labels(names):
    short_names = {name: name.split("::", 1)[-1] for name in names}
    counts = Counter(short_names.values())
    return {name: short if counts[short] == 1 else name for name, short in short_names.items()}
