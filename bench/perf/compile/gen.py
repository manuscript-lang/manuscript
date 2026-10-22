#!/usr/bin/env python3
"""Generate a deterministic multi-module Manuscript project of about 30k lines.

usage: gen.py OUTDIR [UNITS_PER_MODULE]

Each module has UNITS_PER_MODULE units (default 15) of records, alternatives, an interface,
flat matches, loops over lists and maps, string interpolation, Result/try and a generic helper.
The entry module calls every module and prints a checksum.
"""
import os
import sys

MODULES = 30


def unit(k: int) -> str:
    return f'''type R{k}:
    a: Int
    b: Int
    label: String

type S{k}:
    case Low{k}(x: Int)
    case High{k}(x: Int, y: Int)
    case Off{k}

interface Scale{k}:
    fn scaled(by: Int) Int

impl Scale{k} for R{k}:
    fn scaled(by: Int) Int:
        return self.a * by + self.b

fn classify{k}(s: S{k}) Int:
    match s:
        Low{k}(x):
            return x + {k}
        High{k}(x, y):
            return x * y % 97
        Off{k}:
            return 0

fn pick{k}(n: Int) S{k}:
    if n % 3 == 0:
        return Low{k}(n)
    if n % 3 == 1:
        return High{k}(n, {k + 2})
    return Off{k}

fn checked{k}(n: Int) Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative {k}"))
    return ok(n + {k})

fn chain{k}(n: Int) Result[Int, TextError]:
    let v = try checked{k}(n)
    let w = try checked{k}(v % 11)
    return ok(v + w)

fn id{k}[T](x: T) T:
    return x

fn work{k}(seed: Int) Int:
    let r = R{k}(seed, {k}, "r{k}")
    var xs = [seed, {k}, 3]
    var counts = Map[Int, Int]()
    var total = 0
    for i in range(0, 12):
        total += classify{k}(pick{k}(i + seed))
        total += r.scaled(i) % 13
        counts.add(i % 4, i)
    for x in xs:
        total += id{k}(x) % 7
    let text = "{{r.label}}:{{total}}"
    total += text.byte_length()
    if let ok_value = chain{k}(total % 50):
        total += ok_value
    return total

'''


def module(m: int, units: int) -> str:
    out = ['import {TextError} from "@std/core.ms"\nimport {range} from "@std/collections.ms"\n\n']
    for u in range(units):
        out.append(unit(m * units + u))
    body = "\n".join(f"    total += work{m * units + u}(seed + {u})" for u in range(units))
    out.append(f"export fn run{m}(seed: Int) Int:\n    var total = 0\n{body}\n    return total\n")
    return "".join(out)


def main() -> None:
    root = sys.argv[1]
    units = int(sys.argv[2]) if len(sys.argv) > 2 else 15
    src = os.path.join(root, "src")
    os.makedirs(src, exist_ok=True)
    with open(os.path.join(root, "ms.toml"), "w") as f:
        f.write('[project]\nname = "compile-bench"\nsource = "./src"\nentry = "./src/main.ms"\n')
    imports = "".join(f'import {{run{m}}} from "./m{m:02}.ms"\n' for m in range(MODULES))
    calls = "".join(f"    total += run{m}({m})\n    total = total % 1000003\n" for m in range(MODULES))
    with open(os.path.join(src, "main.ms"), "w") as f:
        f.write(
            'import stdout from "@std/io.ms"\n'
            + imports
            + "\nexport fn main() Int:\n    var total = 0\n"
            + calls
            + '    stdout().write("{total}\\n").get()\n    return 0\n'
        )
    for m in range(MODULES):
        with open(os.path.join(src, f"m{m:02}.ms"), "w") as f:
            f.write(module(m, units))


if __name__ == "__main__":
    main()
