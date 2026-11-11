// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "call.method"

import stdout from "@std/io/io.ms"
import max from "@std/math/math.ms"

type Version:
    major: Int

impl Comparable for Version:
    fn compare(other: Version) Int:
        return self.major - other.major

fn main() Unit:
    a := Version(1)
    b := Version(2)
    c: Result[Int, Error] := ok(1)
    e := c.is_ok
    _r := stdout().write("{max(a, b).major} {e}\n")
