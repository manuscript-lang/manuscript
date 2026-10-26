# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "opt.is_some"

from "@std/io.ms" import stdout

def scale(value: Int, by: Int = 2) -> Int: value * by

export def main() -> Int:
    let f = scale
    let g = lambda (value: Int = 4): value
    let r = stdout().write(f"{f(3)} {f(3, 3)} {g()}\n")
    return 0
