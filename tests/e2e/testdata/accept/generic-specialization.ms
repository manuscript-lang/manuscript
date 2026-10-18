import {expect_equal} from "@std/testing.ms"

fn ident[T](x: T) -> T:
    return x

fn countdown[T](x: T, n: Int) -> Int:
    if n == 0:
        return 0

    return 1 + countdown(x: x, n: n - 1)

fn twice[T](x: T) -> T:
    return ident(x: ident(x: x))

fn depth() -> Int:
    return countdown(x: "s", n: 5)

test "static specializations are reused across calls":
    var i = 0
    var acc = 0

    while i < 100:
        acc = acc + ident(x: i)
        i = i + 1

    acc | try expect_equal(expected: 4950)
    ident(x: "a") | try expect_equal(expected: "a")

test "recursive generics with static arguments":
    depth() | try expect_equal(expected: 5)
    countdown(x: 1, n: 3) | try expect_equal(expected: 3)

test "generic calls with type-variable arguments still resolve":
    twice(x: 4) | try expect_equal(expected: 4)
    twice(x: "b") | try expect_equal(expected: "b")
