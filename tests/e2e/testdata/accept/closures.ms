import {expect_equal} from "@std/testing.ms"

fn apply(value: Int, action: fn(value: Int) -> Int) -> Int:
    return action(value: value)

fn countdown[T](value: T, count: Int) -> T:
    if count == 0:
        return value

    return countdown(value: value, count: count - 1)

test "snapshot reassignment and shadowing":
    var offset = 1
    let action = fn(value: Int):
        return value + offset
    offset = 10
    action(value: 3) | try expect_equal(expected: 4)

    if true:
        var offset = 20
        offset = 30
        action(value: offset) | try expect_equal(expected: 31)

    offset | try expect_equal(expected: 10)
    countdown(value: "ready", count: 4) | try expect_equal(expected: "ready")
    let factory = fn(value: Int) -> fn(value: Int) -> Int:
        return fn(value):
            return value + offset
    let nested = factory(value: 99)
    offset = 100
    nested(value: 1) | try expect_equal(expected: 11)
