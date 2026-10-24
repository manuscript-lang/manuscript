# conform: tags=formatter,modules,parser,records,stdlib-math,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/testdata/reject/not-comparable.ms
from "@std/math.ms" import max

type Point:
    x: Int

export def main() -> Int:
    let furthest = max(Point(x: 1), Point(x: 2))
    return furthest.x
