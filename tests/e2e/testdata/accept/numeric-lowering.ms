import {expect_equal, expect_false} from "@std/testing.ms"

type Counter:
    value: Int

fn step(counter: Counter, value: Int) -> Int:
    counter.value = counter.value * 10 + value
    return value

fn identity[T](value: T) -> T:
    return value

test "typed operands retain evaluation order and generic boundaries":
    let counter = Counter(0)
    let total = (
        step(counter: counter, value: 1)
        + step(counter: counter, value: 2) * step(counter: counter, value: 3)
    )
    (total != 7 or counter.value != 123) | try expect_false
    var value = identity(9)
    value = value + 1
    let snapshot = fn() -> Int: return value * 2
    value = value - 1
    (snapshot() != 20 or value != 9) | try expect_false
    (-9223372036854775808 % -1) | try expect_equal(expected: 0)
    (-7 / 2 != -3 or - 7 % 3 != -1) | try expect_false
    (9223372036854775807 * 0) | try expect_equal(expected: 0)

test "floating operations retain binary64 edge behavior":
    let negative_zero = -0.0
    "{1.0 / negative_zero}" | try expect_equal(expected: "-Infinity")
    let nan = 0.0 / 0.0
    (nan <= 0.0 or nan >= 0.0 or nan < 0.0 or nan > 0.0) | try expect_false
    (5e-324 <= 0.0 or 5e-324 / 2.0 != 0.0) | try expect_false
    "{1.7976931348623157e308 * 2.0}" | try expect_equal(expected: "Infinity")
    let a = 1.0000000074505806
    let b = 0.9999999925494194
    (a * b - 1.0) | try expect_equal(expected: 0.0)
