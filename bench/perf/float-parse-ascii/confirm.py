import hashlib
import importlib.util
import json
import os
import argparse
from pathlib import Path

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

ROOT = Path(__file__).resolve().parent
conversion = module("conversion", ROOT / "repeat.py")
old = module("controls", ROOT.parent / "integer-parse-radix" / "repeat.py")
groups = [
    ("float-early", conversion.base, ("float_error", "early", 0), 20000000, ["final-before", "final-aa", "final-after", "final-rust"]),
    ("float-unicode", conversion.base, ("float_error", "unicode", 0), 20000000, ["final-before", "final-aa", "final-after", "final-rust"]),
    ("int-late", old, ("parse_error", "late", 10), 50000, ["final-controls-before", "final-controls-aa", "final-controls-after", None]),
    ("float-plain", conversion.base, ("parse_float", "plain", 0), 2000000, ["final-before", "final-aa", "final-after", "final-rust"]),
]
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary_directory", help="Directory containing the final-* executable names used in groups")
    parser.add_argument("integer_rust", help="Equivalent integer control executable")
    args = parser.parse_args()
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    root = str(Path(args.binary_directory).resolve()) + "/"
    all_paths = {root + name for _, _, _, _, names in groups for name in names if name}
    all_paths.add(str(Path(args.integer_rust).resolve()))
    print(json.dumps(dict(config=True, cpu=cpu, repeats=16, groups=[dict(name=n, case=c, count=k) for n, _, c, k, _ in groups],
                          hashes={path: hashlib.sha256(open(path, "rb").read()).hexdigest() for path in sorted(all_paths)})), flush=True)
    for phase in range(-1, 16):
        cases = groups[phase % len(groups):] + groups[:phase % len(groups)]
        order = list(range(4))
        shift = phase % 4
        order = order[shift:] + order[:shift]
        if phase % 8 >= 4:
            order.reverse()
        for name, runner, case, count, names in cases:
            for label in order:
                binary = root + names[label] if names[label] else str(Path(args.integer_rust).resolve())
                print(json.dumps(dict(name=name, case=case, count=count, phase=phase, label=label, binary=binary,
                                      **runner.run(binary, case, count))), flush=True)

if __name__ == "__main__":
    main()
