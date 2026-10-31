"""Resolve native-library common-path regressions with longer identical-binary controls."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess

parser = argparse.ArgumentParser()
for arg in ["before", "after", "summary", "output"]:
    parser.add_argument(f"--{arg}", type=pathlib.Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
versions = {"baseline-a": args.before.resolve(), "baseline-b": args.before.resolve(), "candidate": args.after.resolve()}
(args.output / "binaries.json").write_text(json.dumps({k: {"path": str(v), "sha256": hashlib.sha256(v.read_bytes()).hexdigest()} for k, v in versions.items()}, indent=2) + "\n")
source = json.loads(args.summary.read_text())
rows = []
for case in ["unicode", "hard-floats"]:
    original = next(r for r in source if r["case"] == case and r["operation"] == "write")
    count = max(1, int(700_000_000 / original["distributions"]["before"]["median_ns"]))
    outputs = [subprocess.check_output([versions[label], case, "ms-output", "0"]) for label in versions]
    if len(set(outputs)) != 1:
        raise ValueError("full output changed")
    unit = len(outputs[0])
    labels = list(versions)
    for trial in range(12):
        order = labels[trial % 3:] + labels[:trial % 3]
        if trial % 2:
            order.reverse()
        for label in order:
            result = subprocess.check_output([versions[label], case, "ms-write", str(count)])
            ns, checksum, observed = map(int, result.split())
            if ns <= 0 or observed != unit or checksum != count * unit:
                raise ValueError("wrong producer count/checksum")
            row = dict(case=case, label=label, trial=trial, count=count, ns=ns / count, unit=unit)
            rows.append(row)
            with (args.output / "samples.jsonl").open("a") as log:
                log.write(json.dumps(row) + "\n")
summary = []
for case in ["unicode", "hard-floats"]:
    distributions = {}
    for label in versions:
        values = [r["ns"] for r in rows if r["case"] == case and r["label"] == label]
        if len(values) != 12:
            raise ValueError("missing samples")
        median = statistics.median(values)
        distributions[label] = dict(median_ns=median, mad_ns=statistics.median(abs(x - median) for x in values), min_ns=min(values), max_ns=max(values))
    summary.append(dict(case=case, distributions=distributions))
(args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
for row in summary:
    print(row["case"], row["distributions"])
