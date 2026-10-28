# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
fn original(value: Int = 7) Int: value + 1

fn replacement(value: Int) Int: value + 2

export fn main() Int:
    var callback = original
    callback = replacement
    return callback(3)
