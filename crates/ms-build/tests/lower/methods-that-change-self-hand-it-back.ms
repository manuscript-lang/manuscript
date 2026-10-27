# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "call.method"
# expect-mir: "store "

interface Counter:
    var def next() -> Int
type C:
    n: Int
impl Counter for C:
    var def next() -> Int:
        self.n += 1
        return self.n
export def main() -> Int:
    var c: Counter = C(0)
    let a = c.next()
    return a + c.next()
