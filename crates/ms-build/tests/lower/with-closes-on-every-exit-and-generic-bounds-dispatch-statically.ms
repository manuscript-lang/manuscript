# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "cleanup.push"
# expect-mir-count: 4 "call @Res.close"

from "@std/core.ms" import Closeable

type Res:
    n: Int

impl Closeable for Res:
    def close() -> Unit:
        let _x = self.n

def run[T: Closeable](r: T, early: Bool) -> Int:
    with let it = r:
        if early:
            return 1
    return 2

export def main() -> Int:
    var i = 0
    while i < 3:
        with let c = Res(i):
            i += 1
            if i == 1:
                continue
            break
    return run(r: Res(1), early: True) + i
