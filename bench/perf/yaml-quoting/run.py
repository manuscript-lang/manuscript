"""Balanced serialization trials; fail closed on producer or semantic mismatches."""
import argparse
import hashlib
import json
import pathlib
import platform
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--before", type=pathlib.Path, required=True)
parser.add_argument("--after", type=pathlib.Path, required=True)
parser.add_argument("--rust", type=pathlib.Path, required=True)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--revision", required=True)
parser.add_argument("--toolchain", required=True)
parser.add_argument("--provenance", type=pathlib.Path, required=True)
parser.add_argument("--repeats", type=int, default=12)
args = parser.parse_args()
if args.repeats < 6 or args.repeats % 6:
    parser.error("use complete six-trial blocks (6, 12, 18, ...) for balanced positions")
root = pathlib.Path(__file__).resolve().parents[3]
provenance = json.loads(args.provenance.read_text())
if provenance["base_commit"] != args.revision:
    raise ValueError("revision does not match build provenance")
required_sources = {
    "bench/perf/yaml-quoting/main.ms", "bench/perf/yaml-quoting/run.py",
    "bench/perf/yaml-quoting/rust/Cargo.toml", "bench/perf/yaml-quoting/rust/Cargo.lock",
    "bench/perf/yaml-quoting/rust/src/main.rs", "Cargo.lock", "rust-toolchain.toml",
    "scripts/lld.lock", "target/ms-native/libms_native.a",
}
if set(provenance["source_and_runtime_sha256"]) != required_sources:
    raise ValueError("incomplete source/runtime provenance")
for source, expected in provenance["source_and_runtime_sha256"].items():
    if hashlib.sha256((root / source).read_bytes()).hexdigest() != expected:
        raise ValueError(f"source changed since build provenance: {source}")
base_source = subprocess.check_output(["git", "show", f"{args.revision}:stdlib/yaml.ms"], cwd=root)
if hashlib.sha256(base_source).hexdigest() != provenance["before_yaml_sha256"]:
    raise ValueError("baseline YAML source digest does not match pinned revision")
if hashlib.sha256((root / "stdlib/yaml.ms").read_bytes()).hexdigest() != provenance["after_yaml_sha256"]:
    raise ValueError("candidate YAML source changed since build provenance")
if set(provenance["build_commands"]) != {"compiler", "before", "after", "rust"}:
    raise ValueError("incomplete build commands")
if not all(provenance["build_commands"].values()):
    raise ValueError("empty build command")
args.output.mkdir(parents=True, exist_ok=False)
versions = {"before": args.before.resolve(), "after": args.after.resolve(), "rust": args.rust.resolve()}
cases = {
    "empty": "",
    "tiny": "Ada",
    "common": "configuration value with spaces, punctuation and 0123456789",
    "ascii-16k": "abcdefgh01234567" * 1024,
    "unicode-16k": "é🙂日本語" * 1024,
    "sparse-escape": "abcdefgh01234567" * 1024 + "\n",
    "dense-escape": '\"\\\n\r\t\b\f\x00\x1f\x7f\x80\x9f' * 1024,
    "mixed-unicode-escape": "é🙂\n日本語\\" * 1024,
}
metadata = {
    "revision": args.revision,
    "toolchain": args.toolchain,
    "platform": platform.platform(),
    "cpu": pathlib.Path("/proc/cpuinfo").read_text().split("model name", 1)[-1].splitlines()[0].strip(" :\t"),
    "binaries": {k: {"path": str(v), "sha256": hashlib.sha256(v.read_bytes()).hexdigest()} for k, v in versions.items()},
    "repeats": args.repeats,
    "provenance": provenance,
    "note": "Native producer timings exclude input/setup/printing. Stringify, full-output equality guard, and output release are timed. Rust may choose different equivalent YAML quoting; byte lengths are recorded independently.",
}
(args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")


def invoke(binary, path, count):
    return subprocess.run([str(binary), str(path), str(count)], capture_output=True, check=True).stdout


def measured(binary, path, count, size):
    fields = invoke(binary, path, count).decode().strip().split("\t")
    if len(fields) != 3:
        raise ValueError(f"malformed timing row: {fields}")
    elapsed, checksum, observed_size = map(int, fields)
    if elapsed <= 0 or checksum != size * count or observed_size != size:
        raise ValueError(f"wrong timing/checksum: {fields}, count={count}, size={size}")
    return elapsed / count


samples = []
for case, text in cases.items():
    path = args.output / f"{case}.txt"
    path.write_text(text)
    sizes = {}
    outputs = {}
    for label, binary in versions.items():
        data = invoke(binary, path, 0)
        outputs[label] = data
        encoded = args.output / f"{case}-{label}.yaml"
        encoded.write_bytes(data)
        subprocess.run([str(versions["rust"]), "--validate", str(path), str(encoded)], capture_output=True, check=True)
        sizes[label] = len(data)
    if outputs["before"] != outputs["after"]:
        raise ValueError(f"before/after output changed: {case}")
    # Calibrate on the baseline, then hold the operation count equal across all versions.
    count = 1
    while True:
        ns = measured(versions["before"], path, count, sizes["before"])
        if ns * count >= 50_000_000 or count >= 1_000_000:
            break
        count = min(max(count + 1, int(count * 60_000_000 / (ns * count))), count * 10, 1_000_000)
    labels = list(versions)
    for trial in range(args.repeats):
        order = labels[trial % 3:] + labels[:trial % 3]
        if trial % 2:
            order.reverse()
        for label in order:
            ns = measured(versions[label], path, count, sizes[label])
            row = {"case": case, "trial": trial, "label": label, "count": count, "ns": ns, "output_bytes": sizes[label]}
            samples.append(row)
            with (args.output / "samples.jsonl").open("a") as log:
                log.write(json.dumps(row) + "\n")

summary = []
for case in cases:
    distributions = {}
    for label in versions:
        values = [r["ns"] for r in samples if r["case"] == case and r["label"] == label]
        if len(values) != args.repeats:
            raise ValueError(f"missing samples: {case}, {label}")
        med = statistics.median(values)
        distributions[label] = {"median_ns": med, "min_ns": min(values), "max_ns": max(values), "mad_ns": statistics.median(abs(x - med) for x in values)}
    row = {"case": case, "distributions": distributions, "before_over_after": distributions["before"]["median_ns"] / distributions["after"]["median_ns"], "after_over_rust": distributions["after"]["median_ns"] / distributions["rust"]["median_ns"]}
    summary.append(row)
# Only emit a summary after every expected case/producer/trial has validated.
(args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
for row in summary:
    print(f'{row["case"]}: before/after={row["before_over_after"]:.3f}x after/rust={row["after_over_rust"]:.3f}x')
