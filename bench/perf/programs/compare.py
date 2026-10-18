"""Compare two already-built revisions against shared handwritten Go samples."""

import argparse
import itertools
from pathlib import Path
import subprocess

from table import summarize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("before", "after", "go", "input", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=30)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("repeats must be positive")
    programs = {name: str(getattr(args, name).resolve()) for name in ("go", "before", "after")}
    orders = list(itertools.permutations(programs))
    raw = {"before": [], "after": []}
    for iteration in range(args.repeats):
        results = {}
        for version in orders[iteration % len(orders)]:
            with args.input.open("rb") as data:
                results[version] = subprocess.run(
                    [programs[version]], stdin=data, capture_output=True, text=True, check=True
                ).stdout
        for revision, lines in raw.items():
            for version, content in (("go", results["go"]), ("ms", results[revision])):
                lines.extend(f"{version} {line}\n" for line in content.splitlines())
    args.output.mkdir(parents=True, exist_ok=True)
    for revision, lines in raw.items():
        (args.output / f"programs-{revision}.txt").write_text("".join(lines))
        table = summarize(lines, args.repeats)
        (args.output / f"programs-{revision}.md").write_text(table + "\n")
        print(revision + "\n" + table)


if __name__ == "__main__":
    main()
