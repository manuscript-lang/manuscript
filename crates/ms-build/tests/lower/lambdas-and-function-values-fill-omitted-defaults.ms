# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "opt.is_some"

import stdout from "@std/io/io.ms"

fn scale(value: Int, by: Int = 2) Int: value * by

export fn main() Int:
    let f = scale
    let g = fn(value: Int = 4): value
    let _r = stdout().write("{f(3)} {f(3, 3)} {g()}\n")
    return 0
