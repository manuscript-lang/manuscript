# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "fn @pad"

fn pad(x: Int, by: Int = 2) Int:
    return x + by

export fn main() Int:
    return pad(1)
