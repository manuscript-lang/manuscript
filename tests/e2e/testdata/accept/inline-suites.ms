import {expect_equal} from "@std/testing.ms"

fn double(value: Int) -> Int: value * 2

fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int: transform(value)

fn choose(value: Int) -> Int:
    if value > 0: return double(value)
    else: return 0

fn alternate(value: Int) -> Int:
    if value < 0: return -1
    else if value == 0: return 0
    else:
        return 1

test "inline functions and branches":
    choose(3) | try expect_equal(expected: 6)
    choose(-3) | try expect_equal(expected: 0)
    alternate(0) | try expect_equal(expected: 0)
    alternate(3) | try expect_equal(expected: 1)
    let increment = fn(value: Int): value + 1
    increment(2) | try expect_equal(expected: 3)
    let result = apply(value: 4, transform: fn(value): value * 3)
    result | try expect_equal(expected: 12)
    var count = 0
    while count < 3: count = count + 1
    count | try expect_equal(expected: 3)

test "inline test": return
