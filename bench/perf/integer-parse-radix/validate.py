"""Validate every retained sample and print all paired measurement tables."""

import collections
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("numeric_repeat", ROOT / "repeat.py")
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)


def validate(path):
    rows = [json.loads(line) for line in path.read_text().splitlines()]
    config = rows[0]
    assert config["config"] and config["repeats"] == 8 and config["count"] == 300000
    labels = list(config["binaries"])
    assert len(labels) == len(set(labels)) == 4
    before, aa, after, rust = labels
    assert config["binaries"][before] == config["binaries"][aa]
    cases = [tuple(case) for case in config["cases"]]
    assert len(cases) == len(set(cases))
    data = rows[1:]
    summaries = [row for row in data if row.get("summary")]
    producers = [row for row in data if not row.get("summary")]
    controls = [row for row in producers if row.get("control")]
    measurements = [row for row in producers if not row.get("control")]
    assert len(controls) == len(cases) * len(labels) * 3
    assert len(measurements) == len(cases) * len(labels) * 9
    assert len(summaries) == len(cases) * len(labels)
    identities = set()
    for row in producers:
        case = tuple(row["case"])
        assert case in cases and row["binary"] in labels
        assert row["count"] > 0
        if row.get("control"):
            assert row["count"] in (1, 2, 1000)
        else:
            scaled = case[0] == "parse_zero" or (
                case[0] == "parse_error" and case[1] in ("overflow-long", "late")
            )
            if path.stem == "sticky-native" and case[0] == "parse_error" and case[1] == "early":
                scaled = True
            assert row["count"] == (config["count"] // 64 if scaled else config["count"])
        assert (row["checksum"], row["last"]) == oracle.expected(case, row["count"])
        assert math.isfinite(row["ns_op"]) and row["ns_op"] >= 0
        assert row["cpu_ns"] >= 0 and row["wall_ns"] > 0
        assert row["ns_op"] * row["count"] <= row["wall_ns"] + 1
        identity = (case, row["binary"], row.get("control", False), row.get("phase"), row["count"])
        assert identity not in identities
        identities.add(identity)
    for phase in range(-1, 8):
        phase_cases = cases[phase % len(cases):] + cases[:phase % len(cases)]
        cycle = phase % 8
        shift = cycle % 4
        order = labels[shift:] + labels[:shift]
        if cycle >= 4:
            order.reverse()
        actual = [row for row in measurements if row["phase"] == phase]
        assert [(tuple(row["case"]), row["binary"]) for row in actual] == [
            (case, label) for case in phase_cases for label in order
        ]
    table = collections.defaultdict(dict)
    for row in measurements:
        if row["phase"] >= 0:
            table[tuple(row["case"])][row["phase"], row["binary"]] = row
    summary_ids = set()
    for row in summaries:
        case, label = tuple(row["case"]), row["binary"]
        assert (case, label) not in summary_ids
        summary_ids.add((case, label))
        values = [table[case][phase, label]["ns_op"] for phase in range(8)]
        for key, value in [("median", statistics.median(values)), ("minimum", min(values)), ("maximum", max(values))]:
            assert math.isclose(row[key], value, rel_tol=1e-12, abs_tol=1e-12)
    print(f"## {path.stem}\n")
    print(f"{len(producers)} successful producer rows: {len(controls)} tiny/output controls, "
          f"{len(cases) * 4} warmups, {len(cases) * 4 * 8} measured.\n")
    print("| Case | Before ns/op | After ns/op | Rust ns/op | Paired after/before | CPU ratio | A/A | Faster pairs |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        group = table[case]
        median = lambda label: statistics.median(group[phase, label]["ns_op"] for phase in range(8))
        ratios = [group[p, after]["ns_op"] / group[p, before]["ns_op"] for p in range(8)]
        aa_ratios = [group[p, aa]["ns_op"] / group[p, before]["ns_op"] for p in range(8)]
        cpu_ratios = [group[p, after]["cpu_ns"] / group[p, before]["cpu_ns"] for p in range(8)]
        rust_value = f"{median(rust):.2f}"
        if path.stem == "sticky-native" and case[0] == "parse_error":
            rust_value = "excluded¹"
        print(f"| {' / '.join(map(str, case))} | {median(before):.2f} | {median(after):.2f} | {rust_value} | "
              f"{statistics.median(ratios):.3f} | {statistics.median(cpu_ratios):.3f} | "
              f"{statistics.median(aa_ratios):.3f} | {sum(ratio < 1 for ratio in ratios)}/8 |")
    print()


if __name__ == "__main__":
    manifest = json.loads((ROOT / "artifacts.json").read_text())
    for relative, expected_hash in manifest["retained_file_sha256"].items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == expected_hash, relative
    for path in [ROOT / "results" / f"{name}.jsonl" for name in ["sticky-native", "native-suffix", "conservative-suffix"]]:
        validate(path)
    print("¹ Sticky-native Rust error timings lack an input optimization barrier and are exploratory only.")
