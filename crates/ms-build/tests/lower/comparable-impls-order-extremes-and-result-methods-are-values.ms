# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "call.method"

import stdout from "@std/io.ms"
import max from "@std/math.ms"

type Version:
    major: Int

impl Comparable for Version:
    fn compare(other: Version) Int:
        return self.major - other.major

export fn main() Int:
    let a = Version(1)
    let b = Version(2)
    let c: Result[Int, Error] = ok(1)
    let e = c.is_ok
    let _r = stdout().write("{max(a, b).major} {e()}\n")
    return 0
