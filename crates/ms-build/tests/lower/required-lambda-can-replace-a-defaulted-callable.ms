# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
fn original(value: Int = 7) Int: value + 1

export fn main() Int:
    var callback = original
    callback = fn(value: Int): value + 2
    return callback(3)
