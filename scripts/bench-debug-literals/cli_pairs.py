"""Measure forced-edit Debug builds with independent before/after ms binaries.

Both binaries must contain the repository's bundled Go SDK. This measures the
whole CLI pipeline, including default lowering followed by Debug selection.
Linux wait4 peak RSS includes child native compiler processes. It is not a
retained-heap measurement. Warm the SDK/cache before comparing measurements.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--prototype", required=True)
    parser.add_argument("--output", default=".artifacts/debug-literals")
    parser.add_argument("--sizes", default="1024,1025,4000,16000,100000")
    parser.add_argument("--count", type=int, default=3)
    args = parser.parse_args()
    root = Path(args.output).resolve()
    root.mkdir(parents=True, exist_ok=True)
    sizes = [int(n) for n in args.sizes.split(",")]
    for n in sizes:
        directory = root / str(n)
        directory.mkdir(exist_ok=True)
        source = ('import List from "@std/collections.ms"\n'
                  'fn values() -> List[Int]:\n    return ['
                  + ", ".join(str(i) for i in range(n)) + ']\n'
                  'export fn main() -> Int:\n'
                  f'    return values().length() - {n}\n')
        (directory / "source.ms").write_text(source)
    binaries = {"baseline": args.baseline, "prototype": args.prototype}
    with (root / "cli-builds.jsonl").open("w") as log:
        for rep in range(args.count):
            for n in sizes:
                directory = root / str(n)
                source = directory / "source.ms"
                names = list(binaries)
                if rep % 2:
                    names.reverse()
                for name in names:
                    # A semantic-neutral source edit invalidates the executable
                    # cache; an unchanged run would measure restoration.
                    with source.open("a") as file:
                        file.write(f"\n# edit {time.time_ns()}\n")
                    binary = directory / (name + ".bin")
                    start = time.monotonic()
                    with (directory / (name + ".build.log")).open("w") as file:
                        child = subprocess.Popen(
                            [binaries[name], "build", str(source),
                             "--build-type", "Debug", "-o", str(binary)],
                            stdout=file, stderr=file,
                        )
                        _, status, usage = os.wait4(child.pid, 0)
                        child.returncode = os.waitstatus_to_exitcode(status)
                    row = dict(rep=rep, n=n, variant=name,
                               wall=time.monotonic() - start,
                               rss=usage.ru_maxrss, exit=child.returncode,
                               size=binary.stat().st_size if binary.exists() else None)
                    print(json.dumps(row), flush=True)
                    log.write(json.dumps(row) + "\n")
                    log.flush()
                    if child.returncode:
                        raise RuntimeError(f"{name} build failed: {directory}")
                    subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
