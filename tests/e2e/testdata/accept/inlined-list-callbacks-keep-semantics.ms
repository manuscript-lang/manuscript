import {expect_true} from "@std/testing.ms"

type Point:
    x: Int

test "inlined callbacks":
    let items = List[Int]()
    var i = 0

    while i < 5:
        items.append(value: i)
        i = i + 1

    let offset = 10
    let shifted = items.map(fn(v: Int) Int: v + offset)
    try expect_true((shifted.length() == 5 and shifted.at(index: 4) == some(14)))
    let labels = items.map(fn(v: Int) String: "n{v}")
    try expect_true((labels.at(index: 2) == some("n2")))
    let floats = items.map(fn(v: Int) Float: 0.5)
    try expect_true((floats.length() == 5))
    let points = items.map(fn(v: Int) Point: Point(x: v))
    try expect_true((points.at(index: 3) == some(Point(x: 3))))
    let evens = items.filter(fn(v: Int) Bool: v % 2 == 0)
    try expect_true((evens.length() == 3))
    try expect_true((points.filter(fn(p: Point) Bool: p.x > 2).length() == 2))
    try expect_true((items.fold(initial: 0, step: fn(a: Int, v: Int) Int: a + v) == 10))
    try expect_true(
        (
            items.fold(
                initial: "",
                step: fn(a: String, v: Int) String: (a + "{v}")
            ) == "01234"
        )
    )
    try expect_true((items.count(predicate: fn(v: Int) Bool: v > 1) == 3))
    try expect_true((items.some(predicate: fn(v: Int) Bool: v == 4)))
    try expect_true((not items.some(predicate: fn(v: Int) Bool: v == 9)))
    try expect_true((items.every(predicate: fn(v: Int) Bool: v < 5)))
    try expect_true((not items.every(predicate: fn(v: Int) Bool: v < 4)))
    let seen = List[Int]()
    items.for_each(
        operation: fn(v: Int) Unit:
            items.append(value: 100)
            seen.append(value: v)
    )
    try expect_true((seen.length() == 5 and items.length() == 10))
    try expect_true((List[Int]().map(fn(v: Int) Int: v).length() == 0))
    try expect_true(
        (
            items.map(
                fn(v: Int) Int: (
                    items
                    .filter(fn(w: Int) Bool: w == v)
                    .length()
                )
            ).length() == 10
        )
    )
