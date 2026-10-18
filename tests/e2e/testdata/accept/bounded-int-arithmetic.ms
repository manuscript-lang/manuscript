import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

fn identity[T](value: T) T: return value

fn bounded_sum() Int:
    var sum = 0
    var i = 0

    while i < 1000:
        sum += identity[Int](i)
        i += 1

    return sum

fn descending_sum() Int:
    var sum = 0
    var i = -1

    while i > -1000:
        sum += i
        i -= 1

    return sum

fn prefix_overflow() Int:
    var sum = 1
    var i = 0

    while i < 1:
        sum += 9223372036854775807
        sum -= 9223372036854775807
        i += 1

    return sum

fn peer_overflow() Int:
    var sum = 9223372036854775807
    var peer = 0
    var i = 0

    while i < 2:
        sum += peer
        peer += 1
        i += 1

    return sum

fn after_step_overflow() Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 1:
        i += 1
        sum += i

    return sum

fn optional_overflow(flag: Bool) Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 1:
        if flag:
            sum += 1
        i += 1

    return sum

fn descending_overflow() Int:
    var sum = -9223372036854775808
    var i = 0

    while i > -1:
        sum -= 1
        i -= 1

    return sum

fn expression_overflow() Int:
    var sum = 0
    var i = 0

    while i < 1:
        let value = match some(1):
            some(n):
                sum = 9223372036854775807
                n
            none: 0

        sum += value
        i += 1

    return sum

fn extreme_endpoints() Int:
    var sum = 9223372036854775803
    var i = 9223372036854775805

    while i < 9223372036854775807:
        sum += 1
        i += 1

    return sum

test "bounded scalar sums preserve values":
    bounded_sum() | try expect_equal(expected: 499500)
    descending_sum() | try expect_equal(expected: -499500)
    extreme_endpoints() | try expect_equal(expected: 9223372036854775805)
    optional_overflow(flag: false) | try expect_equal(expected: 9223372036854775807)

test "intermediate carry updates still fault":
    (try expect_fault(fn(): let ignored = prefix_overflow())) | try expect_contains(
        expected: "Int overflow;"
    )
    (try expect_fault(fn(): let ignored = peer_overflow())) | try expect_contains(
        expected: "Int overflow;"
    )

test "counter phases and optional updates still fault":
    (try expect_fault(fn(): let ignored = after_step_overflow())) | try expect_contains(
        expected: "Int overflow;"
    )
    (try expect_fault(fn(): let ignored = optional_overflow(flag: true))) | try expect_contains(
        expected: "Int overflow;"
    )
    (try expect_fault(fn(): let ignored = descending_overflow())) | try expect_contains(
        expected: "Int overflow;"
    )

test "statement expression writes discard scalar bounds":
    (try expect_fault(fn(): let ignored = expression_overflow())) | try expect_contains(
        expected: "Int overflow;"
    )

fn product_sum() Int:
    var sum = 0
    var i = -100

    while i < 101:
        sum += i * 2
        i += 1

    return sum

fn zero_effect(visits: List[Int]) Int:
    visits.append(1)
    return 9223372036854775807

test "bounded multiplication keeps its operator and operand effects":
    let left = -12
    (left * -7) | try expect_equal(expected: 84)
    product_sum() | try expect_equal(expected: 0)
    let visits: List[Int] = []
    (zero_effect(visits) * 0) | try expect_equal(expected: 0)
    visits | try expect_equal(expected: [1])
