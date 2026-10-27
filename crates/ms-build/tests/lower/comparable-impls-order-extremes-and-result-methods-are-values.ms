# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "call.method"

from "@std/io.ms" import stdout
from "@std/math.ms" import max

type Version:
    major: Int

impl Comparable for Version:
    def compare(other: Version) -> Int:
        return self.major - other.major

export def main() -> Int:
    let a = Version(1)
    let b = Version(2)
    let c: Result[Int, Error] = ok(1)
    let e = c.is_ok
    let _r = stdout().write(f"{max(a, b).major} {e()}\n")
    return 0
