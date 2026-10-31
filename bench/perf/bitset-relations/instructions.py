#!/usr/bin/env python3
"""Count whole-producer instructions; timings under instrumentation are ignored."""

import argparse
import hashlib
import json
import pathlib
import subprocess

import measure


CASES = [(kind, size, pattern, repeats) for kind in ("subset", "superset", "disjoint")
         for size, repeats in [(0, 10000), (1, 10000), (8, 1000), (1024, 10), (65536, 1)]
         for pattern in (["true"] if size == 0 else ["true", "early", "late"])]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=pathlib.Path)
    parser.add_argument("after", type=pathlib.Path)
    parser.add_argument("output_directory", type=pathlib.Path)
    parser.add_argument("--valgrind", default="valgrind")
    args = parser.parse_args()
    if len(CASES) != len(set(CASES)):
        raise ValueError("duplicate workload identities")
    args.output_directory.mkdir()
    output = args.output_directory / "summary.json"
    report = {"complete": False, "cases": [], "binaries": {}}
    output.write_text(json.dumps(report) + "\n")
    report["valgrind"] = subprocess.check_output([args.valgrind, "--version"], text=True).strip()
    report["driver_sha256"] = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    report["validator_sha256"] = hashlib.sha256(pathlib.Path(measure.__file__).read_bytes()).hexdigest()
    report["expected_cases"] = CASES
    report["source_sha256"] = hashlib.sha256(pathlib.Path(__file__).with_name("main.ms").read_bytes()).hexdigest()
    binaries = {name: getattr(args, name).resolve() for name in ("before", "after")}
    for name, binary in binaries.items():
        report["binaries"][name] = {"path": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
    for index, case in enumerate(CASES):
        row = {"case": case}
        for name, binary in binaries.items():
            trace = (args.output_directory / f"{index}-{name}.callgrind").resolve()
            log = (args.output_directory / f"{index}-{name}.log").resolve()
            result = subprocess.run([
                args.valgrind, "--tool=callgrind", f"--callgrind-out-file={trace}",
                f"--log-file={log}", str(binary), *map(str, case),
            ], capture_output=True, text=True, check=True)
            checked = measure.validate_output(result, case)
            lines = trace.read_text().splitlines()
            events = [line for line in lines if line.startswith("events:")]
            totals = [line for line in lines if line.startswith("summary:")]
            if events != ["events: Ir"] or len(totals) != 1:
                raise ValueError(f"missing or unexpected counters in {trace}")
            count = int(totals[0].split()[1])
            if count <= 0:
                raise ValueError(f"invalid instruction count in {trace}")
            row[name] = {"instructions": count, "checksum": checked["checksum"],
                         "exit_status": checked["exit_status"], "trace": str(trace),
                         "trace_sha256": hashlib.sha256(trace.read_bytes()).hexdigest()}
        row["ratio_after_before"] = row["after"]["instructions"] / row["before"]["instructions"]
        report["cases"].append(row)
        output.write_text(json.dumps(report, indent=2) + "\n")
        print(case, row["before"]["instructions"], row["after"]["instructions"],
              f'{row["ratio_after_before"]:.4f}', flush=True)
    report["complete"] = True
    output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
