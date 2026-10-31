# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
import TextError from "@std/core.ms"

fn make(n: Int) Result[String, TextError]:
    if n > 0:
        return ok("x")

    return error(TextError(text: "no"))

fn join(a: String, b: String) String:
    return a + b

fn both(n: Int) Result[String, TextError]:
    return ok(join(a: try make(n), b: try make(n - 1)))

export fn main() Int:
    return 0
