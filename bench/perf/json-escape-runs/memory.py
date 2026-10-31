"""Whole-process RSS controls, separate from timing (not allocation counts)."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess

parser = argparse.ArgumentParser()
for label in ["before", "after", "rust", "rss", "environment", "output"]:
    parser.add_argument(f"--{label}", type=pathlib.Path, required=True)
args = parser.parse_args()
versions = {label: getattr(args, label).resolve() for label in ["before", "after", "rust"]}
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
timing = json.loads(args.environment.read_text())
for label, binary in versions.items():
    if digest(binary) != timing["binaries"][label]["sha256"]:
        raise ValueError("binary differs from timing")
args.output.mkdir(parents=True, exist_ok=False)
metadata = {"binaries": timing["binaries"], "timing_environment_sha256": digest(args.environment),
            "driver_sha256": digest(pathlib.Path(__file__)), "rss_sha256": digest(args.rss),
            "rss_source_sha256": digest(pathlib.Path(__file__).resolve().parents[3] / "bench/perf/representative/rss.c"),
            "note": "Whole-process RSS includes setup and full semantic validation; not allocation counts."}
(args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
rows = []
labels = list(versions)
for case in ["empty", "unicode", "escapes", "integers", "decimals", "hard-floats"]:
    sizes = {}
    outputs = {}
    for label, binary in versions.items():
        prefix = "rust" if label == "rust" else "ms"
        outputs[label] = subprocess.check_output([binary, case, f"{prefix}-output", "0"])
        sizes[label] = len(outputs[label])
    if outputs["before"] != outputs["after"]:
        raise ValueError("byte output changed")
    for trial in range(6):
        order = labels[trial % 3:] + labels[:trial % 3]
        if trial % 2:
            order.reverse()
        for label in order:
            prefix = "rust" if label == "rust" else "ms"
            record = (args.output / f"{case}-{label}-{trial}.json").resolve()
            result = subprocess.check_output([args.rss.resolve(), record, versions[label], case, f"{prefix}-write", "1000"])
            ns, checksum, size = map(int, result.split())
            if ns <= 0 or size != sizes[label] or checksum != 1000 * size:
                raise ValueError("producer checksum/count mismatch")
            rows.append(dict(case=case, label=label, trial=trial, **json.loads(record.read_text())))
expected = {(case, label, trial) for case in ["empty", "unicode", "escapes", "integers", "decimals", "hard-floats"] for label in labels for trial in range(6)}
if len(rows) != len(expected) or {(r["case"], r["label"], r["trial"]) for r in rows} != expected:
    raise ValueError("missing or duplicate RSS records")
(args.output / "samples.json").write_text(json.dumps(rows, indent=2) + "\n")
for case in dict.fromkeys(r["case"] for r in rows):
    print(case, {label: statistics.median(r["maxrss_kib"] for r in rows if r["case"] == case and r["label"] == label) for label in labels})
