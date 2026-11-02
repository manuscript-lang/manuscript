"""Audit retained outputs, sample order, counts, hashes, and all paired tables."""
import collections
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

conversion = module("conversion", ROOT / "repeat.py")
old = module("controls", ROOT.parent / "integer-parse-radix" / "repeat.py")

def output(row, oracle):
    assert (row["checksum"], row["last"]) == oracle.expected(tuple(row["case"]), row["count"])
    assert math.isfinite(row["ns_op"]) and row["ns_op"] >= 0
    assert row["cpu_ns"] >= 0 and row["wall_ns"] > 0
    assert row["ns_op"] * row["count"] <= row["wall_ns"] + 1

def table(title, cases, rows, labels, phases):
    print(f"## {title}\n")
    print("| Case | Before ns/op | After ns/op | Rust ns/op | Paired after/before | CPU ratio | A/A | Faster pairs |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        group = {(r["phase"], r["binary"]): r for r in rows if tuple(r["case"]) == case and r["phase"] >= 0}
        before, aa, after, rust = labels(case) if callable(labels) else labels
        median = lambda label: statistics.median(group[p, label]["ns_op"] for p in range(phases))
        ratios = [group[p, after]["ns_op"] / group[p, before]["ns_op"] for p in range(phases)]
        noise = [group[p, aa]["ns_op"] / group[p, before]["ns_op"] for p in range(phases)]
        cpu = [group[p, after]["cpu_ns"] / group[p, before]["cpu_ns"] for p in range(phases)]
        print(f"| {' / '.join(map(str, case))} | {median(before):.3f} | {median(after):.3f} | {median(rust):.3f} | "
              f"{statistics.median(ratios):.3f} | {statistics.median(cpu):.3f} | {statistics.median(noise):.3f} | "
              f"{sum(v < 1 for v in ratios)}/{phases} |")
    print()

def session(name, oracle, count):
    raw = [json.loads(line) for line in (ROOT / "results" / f"{name}.jsonl").read_text().splitlines()]
    config, rows = raw[0], raw[1:]
    assert config["config"] and config["repeats"] == 8 and config["count"] == count
    cases = [tuple(c) for c in config["cases"]]
    assert cases == oracle.base.CASES if oracle is conversion else cases == old.CASES
    labels = list(config["binaries"])
    assert len(labels) == len(set(labels)) == 4
    assert config["binaries"][labels[0]] == config["binaries"][labels[1]]
    controls = [r for r in rows if r.get("control")]
    measured = [r for r in rows if "phase" in r]
    summaries = [r for r in rows if r.get("summary")]
    assert [(tuple(r["case"]), r["count"], r["binary"]) for r in controls] == [
        (case, tiny, label) for case in cases for tiny in (1, 2, 1000) for label in labels]
    assert len(measured) == len(cases) * 4 * 9
    for phase in range(-1, 8):
        shifted = cases[phase % len(cases):] + cases[:phase % len(cases)]
        cycle = phase % 8
        order = labels[cycle % 4:] + labels[:cycle % 4]
        if cycle >= 4:
            order.reverse()
        actual = [r for r in measured if r["phase"] == phase]
        assert [(tuple(r["case"]), r["binary"]) for r in actual] == [(c, l) for c in shifted for l in order]
    for row in controls + measured:
        output(row, oracle)
        if not row.get("control"):
            op, data, _ = row["case"]
            scale = 1
            if op == "parse_float" and data == "long" or op == "float_error" and data in ("late", "range-long"):
                scale = 128
            elif op == "parse_zero" or op == "parse_error" and data in ("overflow-long", "late"):
                scale = 64
            assert row["count"] == count // scale
    assert [(tuple(r["case"]), r["binary"]) for r in summaries] == [(c, l) for c in cases for l in labels]
    for row in summaries:
        values = [r["ns_op"] for r in measured if r["case"] == row["case"] and r["binary"] == row["binary"] and r["phase"] >= 0]
        for key, value in (("median", statistics.median(values)), ("minimum", min(values)), ("maximum", max(values))):
            assert math.isclose(row[key], value, rel_tol=1e-12, abs_tol=1e-12)
    assert len(rows) == len(controls) + len(measured) + len(summaries)
    print(f"{name}: {len(controls) + len(measured)} producer rows; all outputs, counts, order, and summaries valid.\n")
    table(name, cases, measured, labels, 8)
    return config["binaries"]

def confirmation(hashes):
    raw = [json.loads(line) for line in (ROOT / "results" / "confirmation.jsonl").read_text().splitlines()]
    config, rows = raw[0], raw[1:]
    assert config["config"] and config["repeats"] == 16 and config["hashes"] == hashes
    expected = [("float-early", ("float_error", "early", 0), 20000000),
                ("float-unicode", ("float_error", "unicode", 0), 20000000),
                ("int-late", ("parse_error", "late", 10), 50000),
                ("float-plain", ("parse_float", "plain", 0), 2000000)]
    assert [(g["name"], tuple(g["case"]), g["count"]) for g in config["groups"]] == expected
    assert len(rows) == 4 * 4 * 17
    by_case = collections.defaultdict(dict)
    for row in rows:
        case = tuple(row["case"])
        oracle = old if case[0] == "parse_error" else conversion
        output(row, oracle)
        assert 0 <= row["label"] < 4 and row["binary"] in hashes
        assert row["binary"] == by_case[case].setdefault(row["label"], row["binary"])
    for phase in range(-1, 16):
        groups = expected[phase % 4:] + expected[:phase % 4]
        order = list(range(4))
        order = order[phase % 4:] + order[:phase % 4]
        if phase % 8 >= 4:
            order.reverse()
        actual = [r for r in rows if r["phase"] == phase]
        assert [(r["name"], tuple(r["case"]), r["count"], r["label"]) for r in actual] == [
            (name, case, count, label) for name, case, count in groups for label in order]
    for case, labels in by_case.items():
        assert len(labels) == 4
        assert hashes[labels[0]] == hashes[labels[1]]
        suffix = "final-controls-" if case[0] == "parse_error" else "final-"
        assert Path(labels[0]).name == suffix + "before"
        assert Path(labels[1]).name == suffix + "aa"
        assert Path(labels[2]).name == suffix + "after"
        assert Path(labels[3]).name == ("rust-suffix" if case[0] == "parse_error" else "final-rust")
    print("confirmation: 272 producer rows; all outputs, counts, identities and balanced orders valid.\n")
    table("Long confirmation", [c for _, c, _ in expected], rows, lambda case: [by_case[case][l] for l in range(4)], 16)

if __name__ == "__main__":
    manifest = json.loads((ROOT / "artifacts.json").read_text())
    for path, digest in manifest["retained_file_sha256"].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    hashes = session("conversions", conversion, 1000000)
    hashes.update(session("controls", old, 300000))
    confirmation(hashes)
    matched = json.loads((ROOT / "matched-result.json").read_text())
    for pair in matched["pairs"]:
        assert pair["identical"] and pair["original_sha256"] == pair["matched_sha256"]
        assert pair["original_sha256"] == next(v for k, v in hashes.items() if Path(k).name == pair["original"])
    session("checkpoint-conversions", conversion, 1000000)
    session("checkpoint-controls", old, 300000)
    print("All 4,976 retained producer invocations and matched-location hashes validated. No samples removed.")
