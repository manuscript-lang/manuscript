# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir-order: "fn @main" "drop " "@after"

from "@std/core.ms" import Iterator

type Counter:
    n: Int
    label: String

impl Iterator[Int] for Counter:
    var def next() -> Optional[Int]:
        if self.n == 0: return none
        self.n -= 1
        return some(self.n)

def make() -> Counter:
    return Counter(n: 3, label: "c")

def after() -> Int:
    return 7

export def main() -> Int:
    var total = 0
    for x in make():
        total += x
    return total + after()
