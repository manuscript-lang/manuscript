#!/usr/bin/env python3
"""Build identical runtime overlays; validate first, measure only on request."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess


def run(command, cwd, env, log):
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"exit {result.returncode}: {command}; see {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--go", required=True, type=Path)
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--blocked-iterations", type=int, default=200)
    args = parser.parse_args()
    if args.count < 1 or args.blocked_iterations < 1:
        parser.error("sample count and iterations must be positive")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    template = Path(__file__).with_name("contention.go.txt").read_text()
    go = args.go.resolve()
    env = os.environ.copy()
    env.update(GOMAXPROCS="2", GOFLAGS="-buildvcs=false -p=2")
    env["PATH"] = str(go.parent) + os.pathsep + env["PATH"]
    metadata = {"sdk": subprocess.check_output([str(go), "version"], text=True).strip(),
                "host": platform.platform(), "template_sha256": hashlib.sha256(template.encode()).hexdigest(),
                "environment": {key: env.get(key, "") for key in
                                ["GOMAXPROCS", "GOFLAGS", "GOCACHE", "GOPATH", "GOGC", "GOMEMLIMIT", "XDG_CACHE_HOME"]},
                "samples": args.count, "blocked_iterations": args.blocked_iterations, "commands": [], "revisions": {}}
    for name, tree in [("baseline", args.baseline.resolve()), ("current", args.current.resolve())]:
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=tree, text=True).strip()
        if subprocess.check_output(["git", "diff", "HEAD", "--", "pkg", "internal"], cwd=tree):
            raise RuntimeError(f"uncommitted production changes in {tree}")
        folder = out / name
        folder.mkdir(exist_ok=True)
        source = template.replace("@@GUARD@@", 'return Invoke(ctx, Bind(receiver, "", "get"), nil)' if name == "baseline"
                                  else "return SynchronizedGuardValueRead(ctx, receiver)")
        source = source.replace("@@LOGGER@@", 'return Invoke(ctx, Bind(receiver, "@std/Logger", "level"), nil)' if name == "baseline"
                                else "return LoggerLevelRead(ctx, receiver)")
        generated = folder / "accessor_contention_bench_test.go"
        generated.write_text(source)
        subprocess.run([str(go.parent / "gofmt"), "-w", str(generated)], check=True)
        overlay = folder / "overlay.json"
        overlay.write_text(json.dumps({"Replace": {str(tree / "pkg/runtime/accessor_contention_bench_test.go"): str(generated)}}, indent=2)+"\n")
        metadata["revisions"][name] = {"commit": revision, "worktree": str(tree),
                                      "generated_sha256": hashlib.sha256(generated.read_bytes()).hexdigest()}
        for race in [False, True]:
            binary = folder / ("contention-race.test" if race else "contention.test")
            command = [str(go), "test", "-overlay", str(overlay), "-c", "-o", str(binary)]
            if race:
                command.append("-race")
            command.append("./pkg/runtime")
            metadata["commands"].append(command)
            run(command, tree, env, folder / ("race-build.log" if race else "build.log"))
            command = [str(binary), "-test.run=^TestAccessorContentionParity$", "-test.v", "-test.count=1", "-test.timeout=60s"]
            metadata["commands"].append(command)
            run(command, tree, env, folder / ("race-parity.log" if race else "parity.log"))
    (out / "metadata.json").write_text(json.dumps(metadata, indent=2)+"\n")
    if args.measure:
        samples = []
        # Alternate order to expose directional host drift; retain each raw sample.
        for sample in range(args.count):
            order = ["baseline", "current"] if sample % 2 == 0 else ["current", "baseline"]
            for name in order:
                folder = out / name
                for benchmark, benchtime in [("Uncontended", "200ms"), ("ReleaseLatency", f"{args.blocked_iterations}x")]:
                    command = [str(folder / "contention.test"), "-test.run=^$", f"-test.bench=^BenchmarkAccessor{benchmark}$",
                               f"-test.benchtime={benchtime}", "-test.benchmem", "-test.cpu=2", "-test.count=1", "-test.timeout=120s"]
                    metadata["commands"].append(command)
                    log = folder / f"{benchmark}-{sample+1}.txt"
                    run(command, folder, env, log)
                    for line in log.read_text().splitlines():
                        match = re.match(r"(Benchmark\S+)\s+(\d+)\s+([\d.]+) ns/op\s+([\d.]+) B/op\s+([\d.]+) allocs/op", line)
                        if match:
                            samples.append(dict(revision=name, sample=sample+1, benchmark=match[1], iterations=int(match[2]),
                                                ns_op=float(match[3]), bytes_op=float(match[4]), allocs_op=float(match[5])))
        expected = args.count * 2 * 2 * 4
        if len(samples) != expected:
            raise RuntimeError(f"expected {expected} benchmark records, found {len(samples)}")
        medians = {}
        for sample in samples:
            key = sample["revision"] + "/" + sample["benchmark"]
            medians[key] = {field: statistics.median(row[field] for row in samples
                                                   if row["revision"]+"/"+row["benchmark"] == key)
                            for field in ["ns_op", "bytes_op", "allocs_op"]}
        (out / "samples.json").write_text(json.dumps(samples, indent=2)+"\n")
        (out / "medians.json").write_text(json.dumps(medians, indent=2)+"\n")
        (out / "metadata.json").write_text(json.dumps(metadata, indent=2)+"\n")
    print(f"Validated baseline/current normal and race probes; measurements={args.measure}; evidence={out}")


if __name__ == "__main__":
    main()
