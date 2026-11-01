# conform: tags=closures,control-flow,formatter,generics,lists,match,modules,mutation,optional,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/bounded-int-arithmetic.ms
import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

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
        let value = match present(1):
            n:
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
    bounded_sum() | try expect_equal(499500)
    descending_sum() | try expect_equal(-499500)
    extreme_endpoints() | try expect_equal(9223372036854775805)
    optional_overflow(flag: false) | try expect_equal(9223372036854775807)

test "intermediate carry updates still fault":
    (try expect_fault(fn: let _ignored = prefix_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = peer_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "counter phases and optional updates still fault":
    (try expect_fault(fn: let _ignored = after_step_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = optional_overflow(flag: true))) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = descending_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "statement expression writes discard scalar bounds":
    (try expect_fault(fn: let _ignored = expression_overflow())) | try expect_contains(
        "Int overflow;"
    )

fn product_sum() Int:
    var sum = 0
    var i = -100

    while i < 101:
        sum += i * 2
        i += 1

    return sum

fn zero_effect(var visits: List[Int]) Int:
    visits.append(1)
    return 9223372036854775807

test "bounded multiplication keeps its operator and operand effects":
    let left = -12
    (left * -7) | try expect_equal(84)
    product_sum() | try expect_equal(0)

    var visits: List[Int] = []
    (zero_effect(var visits) * 0) | try expect_equal(0)
    visits | try expect_equal([1])

fn present[T](value: T) T?:
    return value
