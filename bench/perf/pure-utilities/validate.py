#!/usr/bin/env python3
"""Validate every retained utility record and print paired ratios; drop no samples."""
import argparse
import gzip
import hashlib
import itertools
import json
import pathlib
import re
import statistics
import subprocess
import repeat


def allocation_rows(path):
    with gzip.open(path, "rt") as source:
        rows = [json.loads(line) for line in source]
    identity, = [r for r in rows if r["kind"] == "identity"]
    assert all(re.fullmatch("[0-9a-f]{64}", h) for h in identity["binaries"].values())
    samples = [r for r in rows if r["kind"] == "sample"]
    inventory = {c["case"]: c for c in repeat.cases()}
    cases = sorted(set(r["case"] for r in samples))
    for case in cases:
        subset = [r for r in samples if r["case"] == case]
        labels = sorted(set(r["label"] for r in subset))
        assert len(labels) == 2 and len(subset) == 8
        keyed = {(r["count"], r["trial"], r["label"]): r for r in subset}
        assert len(keyed) == 8
        expected = inventory[case]
        unit = sum(len(f.encode()) for f in expected["fields"]) + (expected["status"] == "InvalidData")
        for count, trial, label in itertools.product([1, 100], [0, 1], labels):
            row = keyed[count, trial, label]
            assert label in identity["binaries"]
            assert row["checksum"] == unit * count and row["live"] == 0
            for field in ["allocations", "reallocations", "requested", "peak"]:
                assert row[field] >= 0
                assert row[field] == keyed[count, 0, label][field]
                factor = 1 if field == "peak" else count
                assert row[field] == keyed[1, 0, label][field] * factor
    print(path.name, f"{len(samples)} checked native allocation observations")


def manifest(path):
    here = pathlib.Path(__file__).resolve().parent
    snapshots = {hashlib.sha256(p.read_bytes()).hexdigest() for p in here.rglob("*")
                 if p.is_file() and "results" not in p.relative_to(here).parts
                 and "__pycache__" not in p.parts}
    probe = (here / "allocation-probe.md").read_text().partition("```rust\n")[2].partition("```")[0]
    snapshots.add(hashlib.sha256(probe.encode()).hexdigest())
    for source in ["crates/ms-std-path/src/lib.rs", "crates/ms-std-url/src/lib.rs"]:
        snapshots.add(hashlib.sha256((repeat.ROOT / source).read_bytes()).hexdigest())
    git_hashes = {}
    for entry in json.loads(path.read_text()):
        artifact = path.parent / entry["file"]
        assert hashlib.sha256(artifact.read_bytes()).hexdigest() == entry["gzip_sha256"]
        data = gzip.decompress(artifact.read_bytes())
        assert hashlib.sha256(data).hexdigest() == entry["raw_sha256"]
        rows = [json.loads(line) for line in data.splitlines()]
        assert sum(r["kind"] == "sample" for r in rows) == entry["sample_count"]
        if entry["role"] == "invalid":
            print(artifact.name, "invalid provenance retained, excluded from evidence")
            continue
        identity = rows[0]
        if entry["role"] == "timing":
            validate(artifact)
            revision = identity["revision"]
            for source, wanted in identity["source_sha256"].items():
                if wanted in snapshots:
                    continue
                assert not pathlib.Path(source).is_absolute() and ".." not in pathlib.Path(source).parts
                current = repeat.ROOT / source
                if current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest() == wanted:
                    continue
                key = revision, source
                if key not in git_hashes:
                    blob = subprocess.check_output(["git", "show", f"{revision}:{source}"])
                    git_hashes[key] = hashlib.sha256(blob).hexdigest()
                assert git_hashes[key] == wanted, (artifact.name, source)
        else:
            assert entry["role"] == "allocation"
            allocation_rows(artifact)
            for source in [k for k in identity if k.endswith("source_sha256")]:
                assert identity[source] in snapshots, (artifact.name, source)
    identities = json.loads((path.parent / "identities.json").read_text())
    for kind in ["path", "url"]:
        with gzip.open(path.parent / f"integrated-{kind}-final.jsonl.gz", "rt") as source:
            records = [json.loads(line) for line in source]
        hashes = {r["label"]: r["sha256"] for r in records if r["kind"] == "identity"}
        for label in ["before", "after"]:
            assert hashes[label] == identities["artifacts"][f"{kind}_{label}"]
        assert hashes["rust"] == identities["artifacts"]["rust"]
    assert identities["artifacts"]["url_before"] == identities["artifacts"]["url_after"]
    with gzip.open(path.parent / "integrated-native-allocations.jsonl.gz", "rt") as source:
        native = json.loads(next(source))
    for label in ["before", "after"]:
        assert native["binaries"][label] == identities["artifacts"][f"allocation_{label}"]


def validate(path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt") as source:
        rows = [json.loads(line) for line in source]
    assert all(r["kind"] in {"environment", "identity", "sample", "summary"} for r in rows)
    environment, = [r for r in rows if r["kind"] == "environment"]
    identities = [r for r in rows if r["kind"] == "identity"]
    labels = [r["label"] for r in identities]
    assert len(set(labels)) == len(labels)
    assert all(re.fullmatch("[0-9a-f]{64}", r["sha256"]) for r in identities)
    assert re.fullmatch("[0-9a-f]{40}", environment["revision"])
    assert all(re.fullmatch("[0-9a-f]{64}", h) for h in environment["source_sha256"].values())
    hashes = {r["label"]: r["sha256"] for r in identities}
    for label in labels:
        if label.endswith("-AA"):
            assert hashes[label] == hashes[label.removesuffix("-AA")]
    inventory = {c["case"]: c for c in repeat.cases()}
    cases = {c["case"]: c for c in environment["cases"]}
    assert all(case == inventory[name] for name, case in cases.items())
    samples = [r for r in rows if r["kind"] == "sample"]
    trials = sorted(set(r["trial"] for r in samples))
    assert trials == list(range(-1, max(trials) + 1))
    repeats = len(trials) - 1
    orders = list(itertools.permutations(labels))
    assert repeats > 0 and repeats % len(orders) == 0
    expected_count = len(cases) * len(labels) * len(trials)
    assert len(samples) == expected_count
    keyed = {(r["trial"], r["case"], r["label"]): r for r in samples}
    assert len(keyed) == expected_count
    for trial, case, label in itertools.product(trials, cases, labels):
        row = keyed[trial, case, label]
        expected = cases[case]
        assert row["position"] == orders[(trial + 1) % len(orders)].index(label)
        assert row["status"] == expected["status"] and row["fields"] == expected["fields"]
        unit = sum(len(f.encode()) for f in expected["fields"]) + (expected["status"] == "InvalidData")
        assert row["count"] > 0 and row["ns"] > 0 and row["checksum"] == unit * row["count"]
        assert row["process_cpu_seconds"] >= 0
        assert row["count"] == keyed[trial, case, labels[0]]["count"]
    summary_rows = [r for r in rows if r["kind"] == "summary"]
    summaries = {(r["case"], r["label"]): r for r in summary_rows}
    assert len(summary_rows) == len(summaries)
    assert len(summaries) == len(cases) * len(labels)
    for case, label in itertools.product(cases, labels):
        values = [keyed[t, case, label]["ns"] / keyed[t, case, label]["count"] for t in range(repeats)]
        summary = summaries[case, label]
        assert summary["median_ns"] == statistics.median(values)
        assert summary["min_ns"] == min(values) and summary["max_ns"] == max(values)
    print(path.name, environment["revision"], f"{len(samples)} checked invocations")
    for case in cases:
        ratios = []
        for label in labels[1:]:
            pairs = [keyed[t, case, label]["ns"] / keyed[t, case, labels[0]]["ns"] for t in range(repeats)]
            ratios.append(f"{label}/{labels[0]}={statistics.median(pairs):.4f} [{min(pairs):.4f},{max(pairs):.4f}]")
        print(case, *ratios)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="*", type=pathlib.Path)
    parser.add_argument("--manifest", type=pathlib.Path)
    args = parser.parse_args()
    if args.manifest:
        manifest(args.manifest)
    if not args.files and not args.manifest:
        parser.error("provide files or --manifest")
    for path in args.files:
        validate(path)


if __name__ == "__main__":
    main()
