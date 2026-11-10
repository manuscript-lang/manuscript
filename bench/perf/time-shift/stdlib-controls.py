"""Rerun existing timestamp stdlib cases in alternating compiler order."""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys


def main():
    binaries = sys.argv[1:3]
    output = Path(sys.argv[3])
    pairs = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    suites = [
        ("bench/perf/stdlib/numbers_bench.ms", "time.parse_timestamp", {
            "numbers_bench.ms::time.parse_timestamp": 20000,
            "numbers_bench.ms::time.parse_timestamp_maximum_width": 20000,
            "numbers_bench.ms::time.parse_timestamp_oversized_fraction": 1000,
        }),
        ("bench/perf/stdlib/host_bench.ms", "time.timestamp_to_string", {
            "host_bench.ms::time.timestamp_to_string": 20000,
        }),
    ]
    data = {"revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
            "argv": sys.argv, "cache_home": os.environ.get("XDG_CACHE_HOME"),
            "binary_sha256": {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in binaries},
            "trials": []}
    for pair in range(pairs):
        for source, pattern, expected in suites:
            for side in ([0, 1] if pair % 2 == 0 else [1, 0]):
                command = ["taskset", "-c", "0", binaries[side], "bench", source,
                           "--filter", pattern, "--samples", "11", "--time", "100ms", "--json"]
                result = subprocess.run(command, text=True, capture_output=True, check=True)
                report = json.loads(result.stdout)
                assert len(report["benches"]) == len(expected)
                assert {b["name"] for b in report["benches"]} == set(expected)
                for bench in report["benches"]:
                    assert bench["status"] == "passed", bench
                    assert bench["stats"]["operations"] == expected[bench["name"]], bench
                    assert bench["stats"]["samples"] == 11, bench
                    assert bench["stats"]["median_ns"] > 0, bench
                data["trials"].append({"pair": pair, "side": side, "command": command,
                                       "stdout": result.stdout, "stderr": result.stderr})
                output.write_text(json.dumps(data, separators=(",", ":")) + "\n")
        print(f"pair {pair + 1}/{pairs}", flush=True)
    for _, _, cases in suites:
        for case in cases:
            values = [[], []]
            for trial in data["trials"]:
                for bench in json.loads(trial["stdout"])["benches"]:
                    if bench["name"] == case:
                        values[trial["side"]].append(bench["stats"]["median_ns"])
            before, after = map(statistics.median, values)
            print(case, before, after, after / before)


if __name__ == "__main__":
    main()
