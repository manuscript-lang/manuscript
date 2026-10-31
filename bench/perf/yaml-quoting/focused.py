"""Long paired controls with identical-binary A/A samples; no production edits."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess

parser = argparse.ArgumentParser()
for name in ["before", "after", "rust", "output"]:
    parser.add_argument(f"--{name}", type=pathlib.Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
versions = {"baseline-a": args.before.resolve(), "baseline-b": args.before.resolve(), "candidate": args.after.resolve()}
metadata = {label: {"path": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()} for label, binary in versions.items()}
(args.output / "binaries.json").write_text(json.dumps(metadata, indent=2) + "\n")
rows = []
for case, text, count in [
    ("sparse", "abcdefgh01234567" * 1024 + "\n", 10000),
    ("dense", '\"\\\n\r\t\b\f\x00\x1f\x7f\x80\x9f' * 1024, 3000),
]:
    path = (args.output / f"{case}.txt").resolve()
    path.write_text(text)
    expected = subprocess.check_output([args.before.resolve(), path, "0"])
    if subprocess.check_output([args.after.resolve(), path, "0"]) != expected:
        raise ValueError("before/after output changed")
    encoded = (args.output / f"{case}.yaml").resolve()
    encoded.write_bytes(expected)
    subprocess.run([args.rust.resolve(), "--validate", path, encoded], check=True)
    labels = list(versions)
    for trial in range(12):
        order = labels[trial % 3:] + labels[:trial % 3]
        if trial % 2:
            order.reverse()
        for label in order:
            result = subprocess.check_output([versions[label], path, str(count)])
            ns, checksum, size = map(int, result.split())
            if ns <= 0 or checksum != count * len(expected) or size != len(expected):
                raise ValueError("wrong producer count/checksum")
            row = dict(case=case, label=label, trial=trial, count=count, ns=ns / count, output_bytes=size)
            rows.append(row)
            with (args.output / "samples.jsonl").open("a") as log:
                log.write(json.dumps(row) + "\n")
summary = []
for case in ["sparse", "dense"]:
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
