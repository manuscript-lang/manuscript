# conform: tags=control-flow,faults,interpolation,lists,maps,match,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/text-interpolation-and-map-lookup-keep-semantics.ms
import {expect_true, fail} from "@std/test.ms"

type Point:
    x: Int
    y: Int

fn halve(n: Int) Optional[Int]:
    if n % 2 != 0:
        return none

    return some(value: n / 2)

fn describe(key: Point, m: Map[Point, String]) String:
    match m.get(key: key):
        some(v):
            return "found {v}"
        none:
            return "missing"

test "text interpolation":
    let n = 42
    let f = 1.5
    let ok = true
    let s = "hi"
    try expect_true(("n={n} f={f} ok={ok} s={s}" == "n=42 f=1.5 ok=true s=hi"))
    try expect_true(("{n}" == "42"))
    try expect_true(("{s}{s}" == "hihi"))
    try expect_true(("".length() == 0))
    try expect_true(("héllo {n}".length() == 8))
    try expect_true(("{halve(n: 8)}" == "{halve(n: 8)}"))

    var items = List[Int]()
    items.append(value: 1)
    try expect_true(("{items}" == "[1]"))
    try expect_true(("{Point(x: 1, y: 2)}".length() > 0))

test "map lookup":
    var m = Map[Int, Int]()
    m.add(key: 1, value: 10)

    match m.get(key: 1):
        some(v):
            try expect_true((v == 10))
        none:
            return fail("expected value")

    match m.get(key: 2):
        some(v):
            return fail("unexpected {v}")
        none:
            unit

    var points = Map[Point, String]()
    points.add(key: Point(x: 1, y: 2), value: "a")
    try expect_true((describe(key: Point(x: 1, y: 2), m: points) == "found a"))
    try expect_true((describe(key: Point(x: 2, y: 1), m: points) == "missing"))
