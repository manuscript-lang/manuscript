# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir-order: "fn @main" "drop " "@after"

import Iterator from "@std/core.ms"

type Counter:
    n: Int
    label: String

impl Iterator[Int] for Counter:
    var fn next() Int?:
        if self.n == 0: return none

        self.n -= 1
        return some(self.n)

fn make() Counter:
    return Counter(n: 3, label: "c")

fn after() Int:
    return 7

export fn main() Int:
    var total = 0
    for x in make():
        total += x
    return total + after()
