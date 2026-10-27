# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "call.ind"

from "@std/io.ms" import stdout
from "@std/core.ms" import TextError

def fail() -> Result[Int, TextError]: return error(TextError("no"))

def get(value: Int = try fail()) -> Result[Int, TextError]: return ok(value)

export def main() -> Int:
    let _r = stdout().write(f"{get(2).is_ok()} {get().is_ok()}\n")
    return 0
