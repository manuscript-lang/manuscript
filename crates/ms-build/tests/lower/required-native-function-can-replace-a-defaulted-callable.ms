# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
import floor from "@std/math.ms"

fn original(value: Float = 7.0) Float: value

export fn main() Int:
    var callback = original
    callback = floor

    let _result = callback(3.5)
    return 0
