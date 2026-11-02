#!/usr/bin/env python3
"""Compare exact parser outcomes on deterministic mixed bracket expressions."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("out", type=Path)
    parser.add_argument("--seed", type=int, default=1729)
    parser.add_argument("--cases", type=int, default=1000)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    rng = random.Random(args.seed)
    atoms = ["0", "key", "List[Int]", "fn(Int) Int", "none", "true", "data[0]",
             "(key + 1)", "Int!E", "List[Int, 0]"]

    def expression(depth):
        if depth == 0 or rng.randrange(4) == 0:
            return rng.choice(atoms)
        operation = rng.randrange(5)
        if operation == 0:
            return expression(depth - 1) + "[" + expression(depth - 1) + "]"
        if operation == 1:
            return "data[" + expression(depth - 1) + "]"
        if operation == 2:
            return "(" + expression(depth - 1) + " + " + expression(depth - 1) + ")"
        if operation == 3:
            return expression(depth - 1) + ".field"
        return expression(depth - 1) + "(" + expression(depth - 1) + ")"

    path = args.out / "case.src"
    rows = []
    for index in range(args.cases):
        source = "fn f(data: List[Int]) Int:\n    return " + expression(5) + "\n"
        if index % 3 == 0:
            source = source.replace("\n", "\r\n")
        if index % 7 == 0:
            source = source[:-2]
        path.write_bytes(source.encode())
        before = subprocess.check_output([args.baseline, "outcome", str(path)])
        after = subprocess.check_output([args.candidate, "outcome", str(path)])
        if before != after:
            (args.out / "before.txt").write_bytes(before)
            (args.out / "after.txt").write_bytes(after)
            raise SystemExit(f"outcome mismatch at case {index}; source retained in {path}")
        rows.append({"case": index, "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
                     "outcome_sha256": hashlib.sha256(before).hexdigest(),
                     "accepted": before.startswith(b"Ok(")})
    record = {"seed": args.seed, "cases": rows}
    (args.out / "results.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"{len(rows)} identical outcomes; {sum(row['accepted'] for row in rows)} accepted")


if __name__ == "__main__":
    main()
