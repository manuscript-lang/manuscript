// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
import floor from "@std/math/math.ms"

fn original(value: Float = 7.0) Float: value

fn main() Unit:
    var callback = original
    callback = floor

    _result := callback(3.5)
