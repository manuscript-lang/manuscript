"""Separate whole-process peak RSS controls using the repository's native launcher."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import tomllib

parser = argparse.ArgumentParser()
for label in ["before", "after", "rust", "rss", "timing-environment", "output"]:
    parser.add_argument(f"--{label}", type=pathlib.Path, required=True)
parser.add_argument("--repeats", type=int, default=6)
args = parser.parse_args()
if args.repeats < 6 or args.repeats % 6:
    parser.error("use complete six-trial blocks")
versions = {name: getattr(args, name).resolve() for name in ["before", "after", "rust"]}
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
timing = json.loads(args.timing_environment.read_text())
for label, binary in versions.items():
    if digest(binary) != timing["binaries"][label]["sha256"]:
        raise ValueError(f"binary differs from timing evidence: {label}")
args.output.mkdir(parents=True, exist_ok=False)
root = pathlib.Path(__file__).resolve().parents[3]
metadata = {
    "binaries": timing["binaries"],
    "timing_environment_sha256": digest(args.timing_environment),
    "runner_sha256": digest(pathlib.Path(__file__)),
    "rss_launcher": {"path": str(args.rss.resolve()), "sha256": digest(args.rss)},
    "rss_source_sha256": digest(root / "bench/perf/representative/rss.c"),
    "repeats": args.repeats,
    "note": "Whole-process peak RSS; setup, warm-up and one guarded call included. Not allocation counts or timing evidence.",
}
(args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
cases = {
    "ascii": "abcdefgh01234567" * 65536,
    "unicode": "abcdé🙂日本語" * 65536,
    "sparse": "abcdefgh01234567" * 65536 + "\n",
    "dense": '\"\\\n\r\t\b\f\x00\x1f\x7f' * 65536,
    "mixed": "é🙂\n日本語\\" * 65536,
}
rows = []
labels = list(versions)
for case, text in cases.items():
    path = (args.output / f"{case}.txt").resolve()
    path.write_text(text)
    sizes, outputs = {}, {}
    for label, binary in versions.items():
        data = subprocess.check_output([binary, path, "0"])
        if tomllib.loads(data.decode()) != {"value": text}:
            raise ValueError(f"wrong full output: {case}, {label}")
        outputs[label], sizes[label] = data, len(data)
    if outputs["before"] != outputs["after"]:
        raise ValueError(f"before/after output changed: {case}")
    for trial in range(args.repeats):
        order = labels[trial % 3:] + labels[:trial % 3]
        if trial % 2:
            order.reverse()
        for label in order:
            record = (args.output / f"{case}-{label}-{trial}.json").resolve()
            data = subprocess.check_output([args.rss.resolve(), record, versions[label], path, "1"])
            elapsed, checksum, size = map(int, data.split())
            if elapsed <= 0 or checksum != size or size != sizes[label]:
                raise ValueError(f"wrong timing/checksum: {case}, {label}")
            rows.append(dict(case=case, label=label, trial=trial, input_bytes=path.stat().st_size,
                             input_sha256=digest(path), output_bytes=size,
                             **json.loads(record.read_text())))
expected = {(case, label, trial) for case in cases for label in labels for trial in range(args.repeats)}
if {(r["case"], r["label"], r["trial"]) for r in rows} != expected or len(rows) != len(expected):
    raise ValueError("missing or duplicate memory measurements")
(args.output / "samples.json").write_text(json.dumps(rows, indent=2) + "\n")
for case in cases:
    print(case, {label: statistics.median(r["maxrss_kib"] for r in rows if r["case"] == case and r["label"] == label) for label in labels})
