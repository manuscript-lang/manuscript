"""Fresh zero/one/repeat controls for already-emitted Release prototypes.

Use only the bundled SDK for --go. The common instrumentation is imported from
bench-debug-literals; this does not rebuild or rerun its completed Debug work.
Typed32 is a synthetic Go storage control, not default32 language evidence.
"""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", required=True)
    parser.add_argument("--go", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--cpu", default="1")
    parser.add_argument("--count", type=int, default=5)
    args = parser.parse_args()
    root = Path(args.artifacts).resolve()
    spec = importlib.util.spec_from_file_location(
        "literal_memory", Path(args.repo) / "scripts/bench-debug-literals/memory_controls.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    paths = {
        "baseline": root / "release-reassessment/100000/baseline",
        "reuse256": root / "release-reuse/100000/factory256",
        "typed32": root / "release-typed/100000/typed32",
        "typed64": root / "release-typed/100000/typed64",
    }
    for name, path in paths.items():
        source = (path / "program.go").read_text()
        symbol = re.search(r"(?m)^\t(\w+) = func\(\) rt.Function", source)[1]
        harness = module.HARNESS.replace("FUNCTIONS", symbol).replace(
            "ELEMENTS", "100000").replace("EXPECTED", '[]string{"0"}')
        if name.startswith("typed"):
            harness = harness.replace(
                "list:=v.(*rt.List);if len(list.Items)!=100000",
                "list:=v.(*literalHandle).storage.(*literalOwner);if len(list.items)!=100000",
            ).replace("list.Items[0]", "list.items[0]")
        (path / "memory_test.go").write_text(harness)
        with (path / "memory-build.log").open("w") as log:
            subprocess.run([args.go, "test", "-mod=vendor", "-tags=ms_lean", "-c",
                            "-o", str(path / "memory.test"), str(path / "program.go"),
                            str(path / "memory_test.go")], cwd=args.repo,
                           stdout=log, stderr=log, check=True)
    rng = random.Random(147)
    with (root / "release-reassessment/memory-controls.jsonl").open("w") as log:
        for gc in ("100", "50"):
            for calls in (0, 1, 64):
                for rep in range(args.count):
                    names = list(paths)
                    rng.shuffle(names)
                    for name in names:
                        env = os.environ.copy()
                        env.update(GOGC=gc, GOMAXPROCS="1", LITERAL_MEMORY_CALLS=str(calls))
                        start = time.monotonic()
                        result = subprocess.run(
                            [shutil.which("taskset"), "-c", args.cpu,
                             str(paths[name] / "memory.test"),
                             "-test.run=^TestMemoryControl$", "-test.v"],
                            env=env, text=True, capture_output=True, check=True,
                        )
                        row = json.loads(re.search(r"(?m)^MEMORY (.+)$", result.stdout)[1])
                        row.update(gc=gc, rep=rep, variant=name,
                                   wall=time.monotonic() - start)
                        log.write(json.dumps(row) + "\n")
                        log.flush()


if __name__ == "__main__":
    main()
