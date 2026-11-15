// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "call.ind"

import stdout from "@std/io/io.ms"

fn fail() Result[Int, Error]: return error(Error("no"))

fn get(value: Int = fail()?) Result[Int, Error]: return ok(value)

fn main() Void:
    _r := stdout().write(f"{get(2).is_ok()} {get().is_ok()}\n")
