"""Validate complete sequence-operation producers and retain paired samples.

Usage: measure.py MS_BINARY RUST_BINARY OUTPUT_JSON METADATA_JSON [EVEN_TRIALS]
"""
import hashlib
import json
import platform
import statistics
import subprocess
import sys
from pathlib import Path


def values_for(size, shape):
    random = 1
    values = []
    for i in range(size):
        random = (random * 1103515245 + 12345) % 2147483648
        values.append(i if shape == "ascending" else size - i if shape == "descending"
                      else i % 7 if shape == "duplicate" else random % 100003)
    return values


def expected(operation, size, shape, repeats):
    values = values_for(size, shape)
    if operation in ("sort", "priority"):
        result = sorted(values)
    elif operation == "deque":
        result = values[::2][::-1] + values[1::2]
    else:
        result = values
    return sum((value + 1) * (i + 1) for i, value in enumerate(result)) * repeats


def cases():
    for size in (0, 1, 8, 128, 8192, 100000):
        for operation in ("priority", "queue", "deque"):
            shapes = ("random", "duplicate")
            for shape in shapes:
                yield operation, size, shape, max(2, min(100000, 1000000 // max(size, 1)))


def main():
    manuscript, rust, output, metadata = map(Path, sys.argv[1:5])
    trials = int(sys.argv[5]) if len(sys.argv) > 5 else 6
    if trials < 2 or trials % 2:
        raise ValueError("trials must be positive and even")
    versions = [("ms", manuscript), ("rust", rust)]
    if len(sys.argv) > 6:
        versions.append(("candidate", Path(sys.argv[6])))
    result = {"platform": platform.platform(), "trials": trials,
              "metadata": json.loads(metadata.read_text()), "cases": [],
              "sources": {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                          for name in ("main.ms", "main.rs", "measure.py")},
              "binaries": {name: hashlib.sha256(binary.read_bytes()).hexdigest()
                           for name, binary in versions}}
    required = {"revision", "ms_version", "rust_version", "ms_flags", "rust_flags"}
    if not required <= result["metadata"].keys():
        raise ValueError("metadata must name revision, versions, and flags")
    for operation, size, shape, repeats in cases():
        checksum = expected(operation, size, shape, repeats)
        row = {"operation": operation, "size": size, "shape": shape, "repeats": repeats,
               "checksum": checksum, "samples": []}
        def run(binary):
            completed = subprocess.run([str(binary.resolve()), operation, str(size), shape, str(repeats)],
                                       check=True, capture_output=True, text=True)
            fields = completed.stdout.split()
            if len(fields) != 2:
                raise ValueError(f"incomplete producer: {completed.stdout!r}")
            elapsed, observed = map(int, fields)
            if elapsed <= 0 or observed != checksum:
                raise ValueError(f"bad timing/checksum in {operation}/{size}/{shape}: {fields}, expected {checksum}")
            return elapsed
        for _, binary in versions:
            run(binary)
        for trial in range(trials):
            offset = (trial // 2) % len(versions)
            order = versions[offset:] + versions[:offset]
            for name, binary in order if trial % 2 == 0 else order[::-1]:
                row["samples"].append({"version": name, "trial": trial, "nanoseconds": run(binary)})
        row["median_ns_per_iteration"] = {
            name: statistics.median(sample["nanoseconds"] / repeats
                                    for sample in row["samples"] if sample["version"] == name)
            for name, _ in versions}
        result["cases"].append(row)
    output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
