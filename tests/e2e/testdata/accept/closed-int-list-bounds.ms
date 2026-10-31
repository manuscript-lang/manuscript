import expect_contains, expect_equal, expect_fault from "@std/test.ms"

fn filled_sum() Int:
    var values: List[Int] = []
    var i = 0

    while i < 100:
        values.append(i)
        i += 1

    var sum = 0
    for value in values:
        sum += value
    return sum

fn conditional_length(flag: Bool) Int:
    var values: List[Int] = []
    var i = 0

    while i < 100:
        if flag:
            values.append(i)
        i += 1

    return values.length()

fn self_overflow() Int:
    var values = [0]
    var i = 0

    while i < 2:
        values.append(values.get(-1) + 9223372036854775807)
        i += 1

    return values.get(-1)

fn peer_overflow() Int:
    var values = [0]
    var peer = [9223372036854775807]
    var i = 0

    while i < 2:
        values.append(peer.get(-1))
        peer.append(values.get(-1) + 1)
        i += 1

    return peer.get(-1)

fn prefix_overflow() Int:
    let values = [9223372036854775807, 1, -1]
    var sum = 0
    for value in values:
        sum += value
    return sum

fn optional_overflow(default: Int?) Int:
    let values = [9223372036854775807]
    var sum = 0
    for value in values:
        sum += values.get(0, default)
    return sum + 1

fn effect(var visits: List[Int], value: Int) Int:
    visits.append(value)
    return value

fn mutated_alias() Int:
    let values = [0]
    var alias = values.clone()
    alias.set(0, 9223372036854775807)

    var sum = 0
    for value in values:
        sum += value
    return sum + 1

test "closed list scalar summaries preserve sums and lengths":
    filled_sum() | try expect_equal(4950)
    conditional_length(flag: true) | try expect_equal(100)
    conditional_length(flag: false) | try expect_equal(0)

    let empty: List[Int] = []
    var sum = 0
    for value in empty:
        sum += value
    sum | try expect_equal(0)
    empty.length() | try expect_equal(0)

test "closed list reads preserve defaults and evaluation order":
    let values = [10, 20]
    var visits: List[Int] = []
    values.get(
        default: effect(var visits, 7), index: effect(var visits, 0)
    ) | try expect_equal(10)
    values.get(-1, effect(var visits, 8)) | try expect_equal(20)
    values.get(3, effect(var visits, 9)) | try expect_equal(9)
    visits | try expect_equal([7, 0, 8, 9])

test "recursive appends keep overflow checks":
    (try expect_fault(fn: let _ignored = self_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = peer_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "list prefixes and Optional defaults keep overflow checks":
    (try expect_fault(fn: let _ignored = prefix_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = optional_overflow(none))) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = optional_overflow(0))) | try expect_contains(
        "Int overflow;"
    )

test "a changed copy leaves the original list alone":
    mutated_alias() | try expect_equal(1)

test "append during traversal retains initial-length semantics":
    var values = [1, 2, 3]
    var sum = 0

    for value in values.clone():
        sum += value
        values.append(9)

    sum | try expect_equal(6)
    values.length() | try expect_equal(6)

fn reordered_default_overflow() Int:
    let values = [0]
    var sum = 0
    for value in values:
        sum += values.get(default: 9223372036854775807, index: 2)
    return sum + 1

fn scalar_append_overflow() Int:
    var values: List[Int] = []
    var carry = 0
    var i = 0

    while i < 2:
        values.append(carry)
        carry = 9223372036854775807
        i += 1

    var sum = 0
    for value in values:
        sum += value
    return sum + 1

fn match_length() Int:
    var values: List[Int] = []

    let _ignored = match present(1):
        n:
            values.append(n)
            n
        none: 0

    return values.length()

fn singleton(var values: List[Int]) List[Int]:
    values.append(1)
    return values.clone()

fn default_length() Int:
    var values: List[Int] = []
    let callback = fn(value: List[Int] = singleton(var values)) Int: value.length()
    let _ignored = callback()
    return values.length()

test "reordered defaults and scalar append dependencies keep overflow checks":
    (try expect_fault(fn: let _ignored = reordered_default_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(fn: let _ignored = scalar_append_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "hidden match and default mutations invalidate lengths":
    match_length() | try expect_equal(1)
    default_length() | try expect_equal(1)

fn literal_length_sum() Int:
    let values = [1, 2, 3]
    var sum = 0
    var i = 0

    while i < 321:
        sum += values.length()
        i += 1

    return sum

test "constant length keeps its local valid through partial polling chunks":
    literal_length_sum() | try expect_equal(963)

fn present[T](value: T) T?:
    return value
