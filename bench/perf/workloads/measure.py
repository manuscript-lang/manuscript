"""Time prebuilt CLI workloads, validating every version and trial's output."""
import filecmp
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

VERSIONS = ("ms", "go", "rs")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(directory, version, output):
    executable = directory / version / "app"
    with (directory / "in").open("rb") as stdin, output.open("wb") as stdout:
        start = time.perf_counter_ns()
        result = subprocess.run([str(executable)], cwd=executable.parent,
                                stdin=stdin, stdout=stdout, check=False)
        elapsed = time.perf_counter_ns() - start
    if result.returncode:
        raise ValueError(f"{directory.name}: {version} exited {result.returncode}")
    if elapsed <= 0:
        raise ValueError(f"{directory.name}: nonpositive elapsed time")
    return elapsed


def measure(directory, repeats, name):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    directory = Path(directory).resolve()
    expected = directory / "expected"
    # One untimed run of each version warms executable and input pages. The Go
    # reference establishes the expected bytes; every other output must match.
    run(directory, "go", expected)
    for version in ("ms", "rs"):
        output = directory / version / "out"
        run(directory, version, output)
        filecmp.clear_cache()
        if not filecmp.cmp(expected, output, shallow=False):
            raise ValueError(f"{name}: {version} warm-up output differs from Go")

    samples = []
    for trial in range(repeats):
        offset = trial % len(VERSIONS)
        for version in VERSIONS[offset:] + VERSIONS[:offset]:
            output = directory / version / "out"
            elapsed = run(directory, version, output)
            # filecmp caches results using file metadata. Clear it so a rapid
            # same-size rewrite cannot hide a changed trial on a coarse clock.
            filecmp.clear_cache()
            if not filecmp.cmp(expected, output, shallow=False):
                raise ValueError(f"{name}: {version} trial {trial + 1} output differs from Go")
            samples.append({"trial": trial, "version": version, "elapsed_ns": elapsed})

    evidence = {
        "name": name, "repeats": repeats, "samples": samples,
        "input_sha256": digest(directory / "in"), "output_sha256": digest(expected),
        "binaries_sha256": {v: digest(directory / v / "app") for v in VERSIONS},
    }
    (directory / "samples.json").write_text(json.dumps(evidence, indent=2) + "\n")
    best = {v: min(s["elapsed_ns"] for s in samples if s["version"] == v) for v in VERSIONS}
    m, g, r = (best[v] / 1_000_000 for v in VERSIONS)
    return f"{name:<24} {m:8.3f} {g:8.3f} {r:8.3f} {m/g:7.2f}x {m/r:7.2f}x"


if __name__ == "__main__":
    try:
        print(measure(sys.argv[1], int(sys.argv[2]), sys.argv[3]))
    except (ValueError, OSError, IndexError) as error:
        sys.exit(str(error))
