# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "call.ind"

import stdout from "@std/io.ms"
import TextError from "@std/core.ms"

fn fail() Result[Int, TextError]: return error(TextError("no"))

fn get(value: Int = try fail()) Result[Int, TextError]: return ok(value)

export fn main() Int:
    let _r = stdout().write("{get(2).is_ok()} {get().is_ok()}\n")
    return 0
