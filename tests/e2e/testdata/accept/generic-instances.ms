from "@std/testing.ms" import expect_equal, expect_false

type Point:
    x: Int

def ident[T](x: T) -> T:
    return x

def pick[T](first: Bool, left: T, right: T) -> T:
    var chosen = left
    if not first:
        chosen = right
    return chosen

def keep[T](value: T) -> T:
    let copy = value
    return copy

def count(value: Int) -> Int:
    return value + 1

test "parametric generics keep each instantiation's values":
    try expect_equal(ident(41), 41)
    try expect_equal(ident(1.5), 1.5)
    try expect_equal(ident("go"), "go")
    try expect_false(not ident(True))
    try expect_equal(pick(first: True, left: 1, right: 2), 1)
    try expect_equal(pick(first: False, left: "a", right: "b"), "b")
    try expect_equal(keep(count(1)), 2)

test "instances copy non-scalar arguments":
    let point = Point(3)
    var same = ident(point).clone()
    same.x = 4
    try expect_equal(same.x, 4)
    try expect_equal(point.x, 3)

    var alias = pick(first: True, left: point, right: Point(9)).clone()
    alias.x = 5
    try expect_equal(alias.x, 5)
    try expect_equal(point.x, 3)
