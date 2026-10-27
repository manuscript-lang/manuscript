# conform: tags=closures,control-flow,generics,lists,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/bounded-int-arithmetic.ms
from "@std/test.ms" import expect_contains, expect_equal, expect_fault

def identity[T](value: T) -> T: return value

def bounded_sum() -> Int:
    var sum = 0
    var i = 0

    while i < 1000:
        sum += identity[Int](i)
        i += 1

    return sum

def descending_sum() -> Int:
    var sum = 0
    var i = -1

    while i > -1000:
        sum += i
        i -= 1

    return sum

def prefix_overflow() -> Int:
    var sum = 1
    var i = 0

    while i < 1:
        sum += 9223372036854775807
        sum -= 9223372036854775807
        i += 1

    return sum

def peer_overflow() -> Int:
    var sum = 9223372036854775807
    var peer = 0
    var i = 0

    while i < 2:
        sum += peer
        peer += 1
        i += 1

    return sum

def after_step_overflow() -> Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 1:
        i += 1
        sum += i

    return sum

def optional_overflow(flag: Bool) -> Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 1:
        if flag:
            sum += 1
        i += 1

    return sum

def descending_overflow() -> Int:
    var sum = -9223372036854775808
    var i = 0

    while i > -1:
        sum -= 1
        i -= 1

    return sum

def expression_overflow() -> Int:
    var sum = 0
    var i = 0

    while i < 1:
        let value = match some(1):
            case some(n):
                sum = 9223372036854775807
                n
            case none: 0

        sum += value
        i += 1

    return sum

def extreme_endpoints() -> Int:
    var sum = 9223372036854775803
    var i = 9223372036854775805

    while i < 9223372036854775807:
        sum += 1
        i += 1

    return sum

test "bounded scalar sums preserve values":
    bounded_sum() | try expect_equal(499500)
    descending_sum() | try expect_equal(-499500)
    extreme_endpoints() | try expect_equal(9223372036854775805)
    optional_overflow(flag: False) | try expect_equal(9223372036854775807)

test "intermediate carry updates still fault":
    (try expect_fault(lambda: let ignored = prefix_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = peer_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "counter phases and optional updates still fault":
    (try expect_fault(lambda: let ignored = after_step_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = optional_overflow(flag: True))) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = descending_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "statement expression writes discard scalar bounds":
    (try expect_fault(lambda: let ignored = expression_overflow())) | try expect_contains(
        "Int overflow;"
    )

def product_sum() -> Int:
    var sum = 0
    var i = -100

    while i < 101:
        sum += i * 2
        i += 1

    return sum

def zero_effect(var visits: List[Int]) -> Int:
    visits.append(1)
    return 9223372036854775807

test "bounded multiplication keeps its operator and operand effects":
    let left = -12
    (left * -7) | try expect_equal(84)
    product_sum() | try expect_equal(0)

    var visits: List[Int] = []
    (zero_effect(var visits) * 0) | try expect_equal(0)
    visits | try expect_equal([1])
