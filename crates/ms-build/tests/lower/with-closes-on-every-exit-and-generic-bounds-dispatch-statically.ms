# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "cleanup.push"
# expect-mir-count: 4 "call @Res.close"

import Closeable from "@std/core.ms"

type Res:
    n: Int

impl Closeable for Res:
    fn close() Unit!:
        let _x = self.n
        return ok(unit)

fn run[T: Closeable](r: T, early: Bool) Int:
    var _it = r
    if early:
        return 1

    _it.close().get(none)
    return 2

export fn main() Int:
    var i = 0

    while i < 3:
        let _c = Res(i)
        i += 1
        if i == 1:
            continue

        break

    return run(r: Res(1), early: true) + i
