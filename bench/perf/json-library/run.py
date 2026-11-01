"""Native library-component controls; excludes Manuscript lowering/code generation."""
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
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
versions = {"before": args.before.resolve(), "after": args.after.resolve(), "rust": args.rust.resolve()}
root = pathlib.Path(__file__).resolve().parents[3]
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
files = ["bench/perf/json-library/src/main.rs", "bench/perf/json-library/Cargo.toml", "bench/perf/json-library/Cargo.lock", "bench/perf/json-library/run.py", "crates/ms-std-json/src/lib.rs", "crates/ms-std-json/Cargo.toml", "rust-toolchain.toml", ".cargo/config.toml"]
metadata = {"revision": args.revision, "platform": platform.platform(), "toolchain": subprocess.check_output(["rustc", "-vV"], text=True),
            "binaries": {k: {"path": str(v), "sha256": digest(v)} for k, v in versions.items()},
            "source_sha256": {p: digest(root / p) for p in files},
            "flags": "Cargo release opt-level3 panic=abort; repository force-frame-pointers; same host allocator for library and Serde; native library component, not Manuscript generated code",
            "build": "cargo build --release --locked --manifest-path bench/perf/json-library/Cargo.toml", "trials": 12}
(args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
cases = ["empty", "tiny", "ascii", "unicode", "escapes", "integers", "decimals", "hard-floats"]


def invoke(label, case, operation, count):
    prefix = "rust" if label == "rust" else "ms"
    data = subprocess.check_output([versions[label], case, f"{prefix}-{operation}", str(count)])
    ns, checksum, unit = map(int, data.split())
    if ns <= 0 or unit <= 0 or checksum != unit * count:
        raise ValueError(f"wrong producer result: {label} {case} {operation}")
    return ns / count, unit


samples = []
for case in cases:
    baseline = subprocess.check_output([versions["before"], case, "ms-output", "0"])
    candidate = subprocess.check_output([versions["after"], case, "ms-output", "0"])
    if baseline != candidate:
        raise ValueError(f"Manuscript library output changed: {case}")
    (args.output / f"{case}-ms.json").write_bytes(baseline)
    rust = subprocess.check_output([versions["rust"], case, "rust-output", "0"])
    (args.output / f"{case}-rust.json").write_bytes(rust)
    # Native producers validate full typed values on setup, including exact float round trips.
    for operation in ["write", "parse"]:
        count = 1
        while True:
            ns, _ = invoke("before", case, operation, count)
            if ns * count >= 50_000_000 or count >= 1_000_000:
                break
            count = min(max(count + 1, int(60_000_000 / ns)), count * 10, 1_000_000)
        labels = list(versions)
        units = {}
        for trial in range(12):
            order = labels[trial % 3:] + labels[:trial % 3]
            if trial % 2:
                order.reverse()
            for label in order:
                ns, unit = invoke(label, case, operation, count)
                if units.setdefault(label, unit) != unit:
                    raise ValueError("unit changed across trials")
                row = dict(case=case, operation=operation, label=label, trial=trial, count=count, ns=ns, unit=unit)
                samples.append(row)
                with (args.output / "samples.jsonl").open("a") as log:
                    log.write(json.dumps(row) + "\n")
        if operation == "parse" and len(set(units.values())) != 1:
            raise ValueError("parsed node counts differ")
summary = []
for case in cases:
    for operation in ["write", "parse"]:
        distributions = {}
        for label in versions:
            values = [r["ns"] for r in samples if r["case"] == case and r["operation"] == operation and r["label"] == label]
            if len(values) != 12:
                raise ValueError("missing samples")
            median = statistics.median(values)
            distributions[label] = dict(median_ns=median, mad_ns=statistics.median(abs(x - median) for x in values), min_ns=min(values), max_ns=max(values))
        summary.append(dict(case=case, operation=operation, distributions=distributions,
                            before_over_after=distributions["before"]["median_ns"] / distributions["after"]["median_ns"],
                            after_over_rust=distributions["after"]["median_ns"] / distributions["rust"]["median_ns"] if operation == "write" else None))
(args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
for row in summary:
    print(row["case"], row["operation"], f'library/Rust={row["after_over_rust"] if row["after_over_rust"] is not None else "unmatched parser representation"}', f'before/after={row["before_over_after"]:.3f}x')
