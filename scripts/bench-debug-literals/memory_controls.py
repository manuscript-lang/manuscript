"""Fresh-process startup/retained-memory controls for unused and used literals.

Linux only. Builds both actual CLI paths with bundled Go, captures their cached
Debug Go and compiles the harness against each corresponding runtime workspace.
Heap stats exclude static global tables; direct child /proc RSS/file/anonymous
metrics account for resident data separately. Linux wait4 can retain a pre-exec
parent RSS floor, so it is recorded but excluded from conclusions. No unsafe.
"""

import argparse
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import time


HARNESS = r'''package main
import("testing";"runtime";"encoding/json";"os";"strconv";"strings";"fmt"; rt "github.com/manuscript-lang/manuscript/pkg/runtime")
var retained []rt.Value
func resident() map[string]uint64 {
 data,err:=os.ReadFile("/proc/self/status");if err!=nil {panic(err)}
 result:=map[string]uint64{}
 for _,line:=range strings.Split(string(data),"\n") {f:=strings.Fields(line);if len(f)<2 {continue};switch f[0] {case "VmRSS:","VmHWM:","RssAnon:","RssFile:": n,_:=strconv.ParseUint(f[1],10,64);result[strings.TrimSuffix(f[0],":")]=n*1024}}
 return result
}
func heap() map[string]uint64 {
 var m runtime.MemStats;runtime.ReadMemStats(&m)
 return map[string]uint64{"heap_alloc":m.HeapAlloc,"heap_inuse":m.HeapInuse,"heap_sys":m.HeapSys,"total_alloc":m.TotalAlloc,"stack_inuse":m.StackInuse,"gc_cycles":uint64(m.NumGC)}
}
func TestMemoryControl(t *testing.T) {
 startupHeap:=heap();startupResident:=resident()
 initialize();ctx:=rt.RootExecution()
 functions:=[]rt.Value{FUNCTIONS}
 retained=make([]rt.Value,len(functions))
 calls,err:=strconv.Atoi(os.Getenv("LITERAL_MEMORY_CALLS"));if err!=nil {t.Fatal(err)}
 for i:=0;i<calls;i++ {for j,fn:=range functions {retained[j]=rt.Invoke(ctx,fn,nil)}}
 if calls>0 {for j,v:=range retained {list:=v.(*rt.List);if len(list.Items)!=ELEMENTS {t.Fatal("length")};if fmt.Sprint(list.Items[0])!=EXPECTED[j] {t.Fatal("value",j,list.Items[0])}}}
 // Force collection so the repeated case measures the last retained values,
 // rather than uncollected transient buffers. Static globals stay rooted.
 runtime.GC();runtime.GC()
 result:=map[string]any{"startup_heap":startupHeap,"startup_resident":startupResident,"retained_heap":heap(),"retained_resident":resident(),"calls_per_literal":calls}
 data,err:=json.Marshal(result);if err!=nil {t.Fatal(err)};fmt.Println("MEMORY "+string(data))
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--prototype", required=True)
    parser.add_argument("--go", required=True)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--kind", choices=["Int", "String"], default="Int")
    parser.add_argument("--elements", type=int, default=100000)
    parser.add_argument("--literals", type=int, default=4)
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--cpu", default="0")
    parser.add_argument("--samples-only", action="store_true", help="reuse existing harness binaries")
    args = parser.parse_args()
    root = Path(args.output).resolve()
    root.mkdir(parents=True, exist_ok=True)
    parts = []
    expected = []
    for j in range(args.literals):
        if args.kind == "Int":
            values = [str(j * args.elements + i) for i in range(args.elements)]
            expected.append(str(j * args.elements))
        else:
            values = [json.dumps(f"item:{j}:{i:06}") for i in range(args.elements)]
            expected.append(f"item:{j}:000000")
        parts.append(f"fn values{j}() -> List[{args.kind}]:\n    return [" + ", ".join(values) + "]\n")
    # The source main executes no literal; all tested constructors are reached
    # only through the harness's runtime mode to prevent link-time elimination.
    parts.append("export fn main() -> Int: 0\n")
    source = root / "source.ms"
    source.write_text("".join(parts))
    binaries = {}
    env = os.environ.copy()
    env["MANUSCRIPT_CACHE_DIR"] = args.cache
    for variant, cli in (("baseline", args.baseline), ("prototype", args.prototype)):
        source.write_text(source.read_text() + f"\n# edit {time.time_ns()}\n")
        directory = root / variant
        directory.mkdir(exist_ok=True)
        if args.samples_only:
            binary = directory / "memory.test"
            if not binary.exists():
                raise ValueError("missing existing harness binary")
            binaries[variant] = str(binary)
            continue
        with (directory / "cli-build.log").open("w") as log:
            subprocess.run(["taskset", "-c", "2,3", cli, "build", str(source),
                            "--build-type", "Debug", "-o", str(directory / "program.bin")],
                           env=env, stdout=log, stderr=log, check=True, timeout=240)
        candidates = []
        for file in Path(args.cache).glob("manuscript/workspaces/*/apps/*/main.go"):
            data = file.read_text()
            if str(source) in data and ("debugLiteralData1" in data) == (variant == "prototype"):
                candidates.append(file)
        original = max(candidates, key=lambda file: file.stat().st_mtime_ns)
        data = original.read_text()
        (directory / "main.go").write_text(data)
        starts = list(re.finditer(r"(?m)^\t(\w+) = func\(\) rt.Function \{\n", data))
        symbols = {}
        for i, match in enumerate(starts):
            end = starts[i + 1].start() if i + 1 < len(starts) else len(data)
            body = data[match.start():end]
            for j in range(args.literals):
                if f', "values{j}")' in body:
                    symbols[j] = match[1]
        if len(symbols) != args.literals:
            raise ValueError("could not locate all source constructors")
        harness = HARNESS.replace("FUNCTIONS", ",".join(symbols[j] for j in range(args.literals)))
        harness = harness.replace("ELEMENTS", str(args.elements)).replace(
            "EXPECTED", "[]string{" + ",".join(json.dumps(item) for item in expected) + "}")
        (directory / "memory_test.go").write_text(harness)
        binary = directory / "memory.test"
        # The original app directory resolves its own immutable runtime copy.
        with (directory / "harness-build.log").open("w") as log:
            subprocess.run([args.go, "test", "-mod=vendor", "-tags=ms_lean",
                            "-gcflags=all=-N -l", "-ldflags=-compressdwarf=false", "-c",
                            "-o", str(binary), str(directory / "main.go"),
                            str(directory / "memory_test.go")], cwd=original.parent,
                           stdout=log, stderr=log, check=True, timeout=240)
        binaries[variant] = str(binary)
    rng = random.Random(147)
    with (root / "memory-pairs.jsonl").open("w") as log:
        for gc in ("100", "50"):
            for calls in (0, 1, 64):
                for rep in range(args.count):
                    names = list(binaries)
                    rng.shuffle(names)
                    for variant in names:
                        settings = env.copy()
                        settings.update(GOMAXPROCS="1", GOGC=gc, LITERAL_MEMORY_CALLS=str(calls))
                        start = time.monotonic()
                        with (root / "sample.log").open("w+") as file:
                            # Absolute executable + close_fds=False permits
                            # posix_spawn/vfork. Linux wait4 may still include a
                            # pre-exec RSS floor; direct /proc readings describe
                            # the child image used for the memory conclusions.
                            child = subprocess.Popen([shutil.which("taskset"), "-c", args.cpu, binaries[variant],
                                                      "-test.run=^TestMemoryControl$", "-test.v"],
                                                     env=settings, stdout=file, stderr=file, close_fds=False)
                            _, status, usage = os.wait4(child.pid, 0)
                            child.returncode = os.waitstatus_to_exitcode(status)
                            file.seek(0)
                            output = file.read()
                        if child.returncode:
                            raise RuntimeError(output)
                        row = json.loads(re.search(r"(?m)^MEMORY (.+)$", output)[1])
                        row.update(gc=gc, rep=rep, variant=variant, kind=args.kind,
                                   elements=args.elements, literals=args.literals,
                                   process_wall=time.monotonic() - start, peak_rss_kib=usage.ru_maxrss)
                        print(json.dumps(row), flush=True)
                        log.write(json.dumps(row) + "\n")
                        log.flush()


if __name__ == "__main__":
    main()
