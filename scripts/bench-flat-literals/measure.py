"""Linux build wall time, child-tree peak RSS, binary size and runtime samples.

Run from the checkout root; this only invokes toolchain/go/bin/go. Warm the
runtime/build cache first. Each sample edits the source comment to invalidate
the application cache; executable-cache hits are not compile measurements.
"""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def measure(source, go, timeout):
    binary = source.with_suffix(".bin")
    source.write_text(source.read_text() + f"\n// forced edit {time.time_ns()}\n")
    start = time.monotonic()
    with source.with_suffix(".build.log").open("w") as log:
        command = subprocess.Popen(
            [str(go), "build", "-p", "2", "-mod=vendor", "-tags=ms_lean",
             "-trimpath", "-ldflags=-s -w", "-o", str(binary), str(source)],
            stdout=log, stderr=log, start_new_session=True,
        )
        while True:
            pid, status, usage = os.wait4(command.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() - start > timeout:
                os.killpg(command.pid, signal.SIGTERM)
                _, status, usage = os.wait4(command.pid, 0)
                break
            time.sleep(0.01)
    command.returncode = os.waitstatus_to_exitcode(status)
    record = dict(source=str(source), wall_s=time.monotonic() - start,
                  rss_kb=usage.ru_maxrss, exit=command.returncode)
    if command.returncode == 0:
        record["size"] = binary.stat().st_size
        result = subprocess.run([str(binary.resolve())], capture_output=True, check=True)
        record["output"] = result.stdout.decode() + result.stderr.decode()
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+")
    parser.add_argument("--count", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=240)
    parser.add_argument("--runtime", action="store_true")
    args = parser.parse_args()
    go = (Path.cwd() / "toolchain/go/bin/go").resolve()
    os.environ.update(GOTOOLCHAIN="local", GOPROXY="off", GOSUMDB="off",
                      CGO_ENABLED="0", GOMAXPROCS="2")
    for sample in range(args.count):
        directories = args.directories if sample % 2 == 0 else args.directories[::-1]
        for directory in directories:
            for source in sorted(Path(directory).glob("*/program.go"), key=lambda p: int(p.parent.name)):
                print(json.dumps(measure(source, go, args.timeout)), flush=True)
    if args.runtime:
        for directory in args.directories:
            for source in sorted(Path(directory).glob("*/program.go"), key=lambda p: int(p.parent.name)):
                subprocess.run([str(go), "test", "-mod=vendor", "-tags=ms_lean",
                                "-run=^TestResult$", "-bench=^BenchmarkLiteral$",
                                "-benchmem", "-benchtime=1s", f"-count={args.count}",
                                str(source.parent.resolve())], check=True)


if __name__ == "__main__":
    main()
