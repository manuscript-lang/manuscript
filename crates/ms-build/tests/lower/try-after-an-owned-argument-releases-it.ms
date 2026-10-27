# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
from "@std/core.ms" import TextError

def make(n: Int) -> Result[String, TextError]:
    if n > 0:
        return ok("x")
    return error(TextError(text: "no"))

def join(a: String, b: String) -> String:
    return a + b

def both(n: Int) -> Result[String, TextError]:
    return ok(join(a: try make(n), b: try make(n - 1)))

export def main() -> Int:
    return 0
