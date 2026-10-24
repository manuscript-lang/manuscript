# conform: tags=closures,control-flow,faults,formatter,interpolation,lists,modules,mutation,numbers,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/inlined-list-callbacks-keep-semantics.ms
from "@std/testing.ms" import expect_true

type Point:
    x: Int

test "inlined callbacks":
    var items = List[Int]()
    var i = 0

    while i < 5:
        items.append(value: i)
        i = i + 1

    let offset = 10
    let shifted = items.map(lambda (v: Int) -> Int: v + offset)
    try expect_true((shifted.length() == 5 and shifted.get(index: 4) == 14))

    let labels = items.map(lambda (v: Int) -> String: f"n{v}")
    try expect_true((labels.get(index: 2) == "n2"))

    let floats = items.map(lambda (v: Int) -> Float: 0.5)
    try expect_true((floats.length() == 5))

    let points = items.map(lambda (v: Int) -> Point: Point(x: v))
    try expect_true((points.get(index: 3) == Point(x: 3)))

    let evens = items.filter(lambda (v: Int) -> Bool: v % 2 == 0)
    try expect_true((evens.length() == 3))
    try expect_true((points.filter(lambda (p: Point) -> Bool: p.x > 2).length() == 2))
    try expect_true((items.fold(initial: 0, step: lambda (a: Int, v: Int) -> Int: a + v) == 10))
    try expect_true(
        (
            items.fold(
                initial: "", step: lambda (a: String, v: Int) -> String: (a + f"{v}")
            ) == "01234"
        )
    )
    try expect_true((items.count(predicate: lambda (v: Int) -> Bool: v > 1) == 3))
    try expect_true((items.some(predicate: lambda (v: Int) -> Bool: v == 4)))
    try expect_true((not items.some(predicate: lambda (v: Int) -> Bool: v == 9)))
    try expect_true((items.every(predicate: lambda (v: Int) -> Bool: v < 5)))
    try expect_true((not items.every(predicate: lambda (v: Int) -> Bool: v < 4)))

    # Closures cannot mutate captures, so iterate a clone while growing the original.
    var seen = List[Int]()

    for v in items.clone():
        items.append(value: 100)
        seen.append(value: v)

    try expect_true((seen.length() == 5 and items.length() == 10))
    try expect_true((List[Int]().map(lambda (v: Int) -> Int: v).length() == 0))
    try expect_true(
        (
            items.map(
                lambda (v: Int) -> Int: (
                    items
                    .filter(lambda (w: Int) -> Bool: w == v)
                    .length()
                )
            ).length() == 10
        )
    )
