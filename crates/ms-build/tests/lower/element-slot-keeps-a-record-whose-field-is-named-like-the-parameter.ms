# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "store %"

type Child:
    value: Int

export fn main() Int:
    var values = [Child(1), Child(1)]
    let c = Child(9)
    values.fill(c, 0, 1)
    return values.length()
