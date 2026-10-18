import {expect_equal} from "@std/testing.ms"

fn pair(a: Int, b: Int) -> Int: a * 10 + b

test "arguments":
    var value = 1
    let option: Optional[Int] = some(2)
    let result = pair(
        a: value,
        b: match option:
            some(i):
                value = 9
                i
            none: 0
    )
    result | try expect_equal(expected: 12)

fn optional(value: Optional[Int]) -> Int: value.unwrap()

fn defaulted(value: Int = 3) -> Int: value

fn identity[T](value: T) -> T: value

test "source call dispatch contracts":
    optional(4) | try expect_equal(expected: 4)
    defaulted(5) | try expect_equal(expected: 5)
    defaulted() | try expect_equal(expected: 3)
    pair(b: 2, a: 1) | try expect_equal(expected: 12)
    let callback = pair
    callback(a: 3, b: 4) | try expect_equal(expected: 34)
    identity(6) | try expect_equal(expected: 6)
