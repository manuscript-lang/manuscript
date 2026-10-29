# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "list.addr.u"
# expect-mir: "store "
# expect-mir-count: 1 "load list<int>"
fn fill(f: fn(Int) Unit) Unit:
    f(0)
    f(1)

export fn main() Int:
    var out: List[Int] = [0, 0]
    fill(fn r: out[r] = r + 5)
    return out[1]
