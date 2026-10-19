# conform: tags=aliasing,control-flow,formatter,generics,modules,mutation,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/generic-instances.ms
import {expect_equal, expect_false} from "@std/testing.ms"

type Point:
    x: Int

fn ident[T](x: T) T:
    return x

fn pick[T](first: Bool, left: T, right: T) T:
    var chosen = left
    if not first:
        chosen = right
    return chosen

fn keep[T](value: T) T:
    let copy = value
    return copy

fn count(value: Int) Int:
    return value + 1

test "parametric generics keep each instantiation's values":
    try expect_equal(ident(41), 41)
    try expect_equal(ident(1.5), 1.5)
    try expect_equal(ident("go"), "go")
    try expect_false(not ident(true))
    try expect_equal(pick(first: true, left: 1, right: 2), 1)
    try expect_equal(pick(first: false, left: "a", right: "b"), "b")
    try expect_equal(keep(count(1)), 2)

test "instances share one identity for non-scalar arguments":
    let point = Point(3)
    var same = ident(point)
    same.x = 4
    try expect_equal(point.x, 4)
    var alias = pick(first: true, left: point, right: Point(9))
    alias.x = 5
    try expect_equal(point.x, 5)
