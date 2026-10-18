import {expect_equal, expect_true} from "@std/testing.ms"

type Point:
    x: Int

fn ident[T](x: T) -> T:
    return x

fn pick[T](first: Bool, left: T, right: T) -> T:
    var chosen = left
    if not first:
        chosen = right
    return chosen

fn keep[T](value: T) -> T:
    let copy = value
    return copy

fn count(value: Int) -> Int:
    return value + 1

test "parametric generics keep each instantiation's values":
    ident(x: 41) | try expect_equal(expected: 41)
    ident(x: 1.5) | try expect_equal(expected: 1.5)
    ident(x: "go") | try expect_equal(expected: "go")
    (ident(x: true)) | try expect_true
    pick(first: true, left: 1, right: 2) | try expect_equal(expected: 1)
    pick(first: false, left: "a", right: "b") | try expect_equal(expected: "b")
    keep(value: count(value: 1)) | try expect_equal(expected: 2)

test "instances share one identity for non-scalar arguments":
    let point = Point(x: 3)
    let same = ident(x: point)
    same.x = 4
    point.x | try expect_equal(expected: 4)
    let alias = pick(first: true, left: point, right: Point(x: 9))
    alias.x = 5
    point.x | try expect_equal(expected: 5)
