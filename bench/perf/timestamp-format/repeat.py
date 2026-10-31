#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import platform
import resource
import statistics
import subprocess
import time

CASES = {
    "whole": [(1710073815, 0), (1710073816, 0)],
    "millis": [(1710073815, 250000000), (1710073816, 120000000)],
    "nanos": [(1710073815, 123456789), (1710073816, 999999999)],
    "leading": [(1710073815, 1), (1710073816, 10)],
    "limits": [(-62135596800, 0), (253402300799, 999999999)],
    "mixed": [(-1, 0), (0, 100000000)],
}

def expected(seconds, nanos):
    dt = datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc)
    text = f"{dt.year:04}-{dt.month:02}-{dt.day:02}T{dt.hour:02}:{dt.minute:02}:{dt.second:02}"
    return text + ("." + f"{nanos:09}".rstrip("0") if nanos else "") + "Z"

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--producer", action="append", required=True)
    p.add_argument("--count", type=int, default=200000)
    p.add_argument("--repeats", type=int, default=12)
    p.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    args = p.parse_args()
    assert args.count > 0 and args.count % 2 == 0
    os.sched_setaffinity(0, {args.cpu})
    root = pathlib.Path(__file__).resolve().parents[3]
    paths = ["crates/ms-std-time/src/core_time.rs", "toolchain/lld.lock", "rust-toolchain.toml",
             "bench/perf/timestamp-format/main.ms", "bench/perf/timestamp-format/rust/src/main.rs",
             "bench/perf/timestamp-format/rust/Cargo.toml", "bench/perf/timestamp-format/rust/Cargo.lock",
             "bench/perf/timestamp-format/repeat.py"]
    print(json.dumps({"kind":"environment",
                      "revision":subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,text=True).strip(),
                      "source_sha256":{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths},
                      "rustc":subprocess.check_output(["rustc","--version"],text=True).strip(),
                      "cargo":subprocess.check_output(["cargo","--version"],text=True).strip(),
                      "machine":{k:v for k,v in platform.uname()._asdict().items() if k!="node"},
                      "selectors":{k:os.environ.get(k) for k in ["MS_BACKEND","MS_LLVM_TOOLS"]}}),flush=True)
    producers=[]
    for item in args.producer:
        label, spec=item.split("=",1)
        binary, *mode=spec.split("::")
        binary=os.path.abspath(binary)
        producers.append((label,[binary]+mode))
        print(json.dumps({"kind":"identity","label":label,"binary":binary,
                          "sha256":hashlib.sha256(open(binary,"rb").read()).hexdigest(),"cpu":args.cpu}),flush=True)
    rows=[]
    cases=list(CASES)
    for trial in range(-1,args.repeats):
        rotation=max(0,trial)%len(cases)
        for case in cases[rotation:]+cases[:rotation]:
            values=CASES[case]
            wants=[expected(*v) for v in values]
            order=producers if trial%2==0 else list(reversed(producers))
            for label,command in order:
                started=time.monotonic_ns()
                cpu_before=resource.getrusage(resource.RUSAGE_CHILDREN)
                output=subprocess.run(command+[str(args.count)]+[str(n) for v in values for n in v]+wants,
                                      check=True,capture_output=True,text=True,timeout=60)
                cpu_after=resource.getrusage(resource.RUSAGE_CHILDREN)
                assert not output.stderr
                count,ns,checksum,last=output.stdout.removesuffix("\n").split("\t",3)
                assert int(count)==args.count and 0<int(ns)<time.monotonic_ns()-started
                assert int(checksum)==args.count//2*sum(map(len,wants)) and last==wants[1]
                row={"kind":"sample","trial":trial,"case":case,"label":label,
                     "count":int(count),"ns":int(ns),"checksum":int(checksum),"last":last,
                     "process_cpu_seconds":cpu_after.ru_utime+cpu_after.ru_stime-cpu_before.ru_utime-cpu_before.ru_stime}
                print(json.dumps(row),flush=True)
                if trial>=0: rows.append(row)
    for case in cases:
        for label,_ in producers:
            samples=[r['ns']/r['count'] for r in rows if r['case']==case and r['label']==label]
            assert len(samples)==args.repeats
            print(json.dumps({"kind":"summary","case":case,"label":label,
                              "median_ns":statistics.median(samples),"min_ns":min(samples),"max_ns":max(samples)}),flush=True)

if __name__=="__main__": main()
