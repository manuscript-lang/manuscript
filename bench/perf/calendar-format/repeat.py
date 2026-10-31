#!/usr/bin/env python3
"""Balanced, exact-output checked calendar-format measurements; no dropped samples."""
import argparse
import datetime
import hashlib
import json
import os
import platform
import pathlib
import resource
import statistics
import subprocess
import time

PATTERNS = {
    "empty": "",
    "literal": "calendar report",
    "year": "YYYY",
    "date": "YYYY-MM-DD",
    "datetime": "YYYY-MM-DD HH:mm:ss",
    "all": "YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]",
    "repeat": "YYYYMMDDHHmmssSSSZZzone" * 16,
    "literal-large": "calendar report / " * 256,
    "prefixes": "YYY M D H m s SS Z zon ",
    "unicode": "日付 YYYY 年 MM 月 DD 日 🕰 HH:mm:ss",
}
TOKENS = ["YYYY", "MM", "DD", "HH", "mm", "ss", "SSS", "ZZ", "zone"]


def expected(pattern, seconds):
    t = datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc)
    values = [f"{t.year:04}", f"{t.month:02}", f"{t.day:02}", f"{t.hour:02}",
              f"{t.minute:02}", f"{t.second:02}", "250", "+00:00", "UTC"]
    out = ""
    while pattern:
        for key, value in zip(TOKENS, values):
            if pattern.startswith(key):
                out += value
                pattern = pattern[len(key):]
                break
        else:
            out += pattern[0]
            pattern = pattern[1:]
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--producer", action="append", required=True,
                        help="label=/absolute/binary[::mode], where mode is rust or native")
    parser.add_argument("--repeats", type=int, default=8)
    parser.add_argument("--count", type=int, default=200000)
    parser.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    parser.add_argument("--case", action="append", choices=list(PATTERNS))
    args = parser.parse_args()
    assert args.count > 0 and args.count % 2 == 0
    os.sched_setaffinity(0, {args.cpu})
    root = pathlib.Path(__file__).resolve().parents[3]
    source_paths = ["crates/ms-std-time/src/core_time.rs", "toolchain/lld.lock",
                    "rust-toolchain.toml", "bench/perf/calendar-format/main.ms",
                    "bench/perf/calendar-format/rust/src/main.rs",
                    "bench/perf/calendar-format/rust/Cargo.toml",
                    "bench/perf/calendar-format/rust/Cargo.lock",
                    "bench/perf/calendar-format/repeat.py"]
    print(json.dumps({"kind": "environment",
                      "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                      "source_sha256": {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in source_paths},
                      "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                      "cargo": subprocess.check_output(["cargo", "--version"], text=True).strip(),
                      "selectors": {k: os.environ.get(k) for k in ["MS_BACKEND", "MS_LLVM_TOOLS"]}}), flush=True)
    producers = []
    for item in args.producer:
        label, spec = item.split("=", 1)
        binary, *mode = spec.split("::")
        binary = os.path.abspath(binary)
        producers.append((label, [binary] + mode))
        print(json.dumps({"kind": "identity", "label": label, "path": binary,
                          "sha256": hashlib.sha256(open(binary, "rb").read()).hexdigest(),
                          "machine": {k: v for k, v in platform.uname()._asdict().items() if k != "node"},
                          "cpu": args.cpu}), flush=True)
    cases = args.case or list(PATTERNS)
    rows = []
    for trial in range(-1, args.repeats):
        rotated = cases[max(trial, 0) % len(cases):] + cases[:max(trial, 0) % len(cases)]
        for case in rotated:
            pattern = PATTERNS[case]
            # Large cases keep total work bounded, with the same count for every producer.
            count = max(2, args.count // max(1, len(pattern) // 32)) // 2 * 2
            want = expected(pattern, 1710073816)
            assert len(expected(pattern, 1710073815).encode()) == len(want.encode())
            order = producers if trial % 2 == 0 else list(reversed(producers))
            for label, command in order:
                start = time.monotonic_ns()
                cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
                proc = subprocess.run(command + [str(count), pattern,
                                                expected(pattern, 1710073815), want],
                                      capture_output=True, text=True, timeout=60, check=True)
                cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN)
                if proc.stderr:
                    raise ValueError(proc.stderr)
                fields = proc.stdout.removesuffix("\n").split("\t", 3)
                if len(fields) != 4:
                    raise ValueError(proc.stdout)
                found_count, ns, checksum = map(int, fields[:3])
                assert found_count == count and checksum == len(want.encode()) * count
                assert fields[3] == want and 0 < ns < time.monotonic_ns() - start
                row = {"kind": "sample", "trial": trial, "case": case, "label": label,
                       "count": count, "ns": ns, "checksum": checksum, "last": fields[3],
                       "process_cpu_seconds": cpu_after.ru_utime + cpu_after.ru_stime - cpu_before.ru_utime - cpu_before.ru_stime}
                print(json.dumps(row), flush=True)
                if trial >= 0:
                    rows.append(row)
    for case in cases:
        for label, _ in producers:
            values = [r["ns"] / r["count"] for r in rows
                      if r["case"] == case and r["label"] == label]
            assert len(values) == args.repeats
            print(json.dumps({"kind": "summary", "case": case, "label": label,
                              "median_ns": statistics.median(values),
                              "min_ns": min(values), "max_ns": max(values)}), flush=True)


if __name__ == "__main__":
    main()
