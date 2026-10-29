# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "call.method"
# expect-mir: "store "

interface Counter:
    var fn next() Int

type C:
    n: Int

impl Counter for C:
    var fn next() Int:
        self.n += 1
        return self.n

export fn main() Int:
    var c: Counter = C(0)
    let a = c.next()
    return a + c.next()
