# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
from "@std/math.ms" import floor
def original(value: Float = 7.0) -> Float: value
export def main() -> Int:
    var callback = original
    callback = floor
    let result = callback(3.5)
    return 0
