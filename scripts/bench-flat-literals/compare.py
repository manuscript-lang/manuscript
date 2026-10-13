"""Generate controlled Go representation candidates from the frozen scalar emitter.

Input is bench-flat-literals output from the independent pre-change checkout.
The optional effectful comparison isolates Go SSA size using a handwritten
side-effecting scalar call; use main.go -effectful for actual source-call costs.
"""

import argparse
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline")
    parser.add_argument("--output", default=".artifacts/flat-literals/candidates")
    parser.add_argument("--effectful", action="store_true")
    args = parser.parse_args()
    for source in Path(args.baseline).glob("*/program.go"):
        text = source.read_text()
        match = re.search(r'&rt.List\{Type: "@std/List\[Int\]", Items: \[\]rt.Value\{(.*?)\}\}', text)
        if match is None:
            raise ValueError("input must be the independent scalar emitter output")
        n = int(source.parent.name)
        values = match.group(1).split(", ")
        assert len(values) == n
        declaration = ""
        harness = source.with_name("program_test.go").read_text()
        if args.effectful:
            values = ["dynamicValue()"] * n
            declaration = "\nvar dynamicCounter int64\nfunc dynamicValue() rt.Value {dynamicCounter++; return dynamicCounter}\n"
            # Each parity evaluation starts the handwritten counter afresh.
            harness = harness.replace("func TestResult(t *testing.T) {", "func TestResult(t *testing.T) {dynamicCounter = 0;")
            harness = harness.replace("i + 0", "i + 1")
        candidates = {"literal": (f'&rt.List{{Type: "@std/List[Int]", Items: []rt.Value{{{", ".join(values)}}}}}', declaration)}
        if not args.effectful:
            candidates["copy"] = (
                f'func() rt.Value {{items := make([]rt.Value, {n}); copy(items, literalData[:]); return &rt.List{{Type: "@std/List[Int]", Items: items}}}}()',
                "\nvar literalData = [...]rt.Value{" + ", ".join(values) + "}\n",
            )
            candidates["typed"] = (
                'func() rt.Value {data := []int64{' + ", ".join(str(i) for i in range(n)) + '}; items := make([]rt.Value, len(data)); for i, value := range data {items[i] = value}; return &rt.List{Type: "@std/List[Int]", Items: items}}()', "",
            )
        for size in (64, 256, 1024):
            body = f"func() rt.Value {{items := make([]rt.Value, {n}); "
            for at in range(0, n, size):
                if args.effectful:
                    statements = ";".join(f"items[{i}] = dynamicValue()" for i in range(at, min(at + size, n)))
                else:
                    statements = f"copy(items[{at}:], []rt.Value{{{', '.join(values[at:at + size])}}})"
                body += "func() {" + statements + "}(); "
            body += 'return &rt.List{Type: "@std/List[Int]", Items: items}}()'
            candidates[f"chunk{size}"] = (body, declaration)
        for name, (body, extra) in candidates.items():
            directory = Path(args.output) / name / str(n)
            directory.mkdir(parents=True, exist_ok=True)
            directory.joinpath("program.go").write_text(text[:match.start()] + body + text[match.end():] + extra)
            directory.joinpath("program_test.go").write_text(harness)


if __name__ == "__main__":
    main()
