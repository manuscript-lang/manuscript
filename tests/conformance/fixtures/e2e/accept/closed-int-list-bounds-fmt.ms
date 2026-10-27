# conform: tags=aliasing,closures,control-flow,faults,formatter,lists,match,modules,mutation,optional,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/closed-int-list-bounds.ms
from "@std/test.ms" import expect_contains, expect_equal, expect_fault

def filled_sum() -> Int:
    var values: List[Int] = []
    var i = 0

    while i < 100:
        values.append(i)
        i += 1

    var sum = 0
    for value in values:
        sum += value
    return sum

def conditional_length(flag: Bool) -> Int:
    var values: List[Int] = []
    var i = 0

    while i < 100:
        if flag:
            values.append(i)
        i += 1

    return values.length()

def self_overflow() -> Int:
    var values = [0]
    var i = 0

    while i < 2:
        values.append(values.get(-1) + 9223372036854775807)
        i += 1

    return values.get(-1)

def peer_overflow() -> Int:
    var values = [0]
    var peer = [9223372036854775807]
    var i = 0

    while i < 2:
        values.append(peer.get(-1))
        peer.append(values.get(-1) + 1)
        i += 1

    return peer.get(-1)

def prefix_overflow() -> Int:
    let values = [9223372036854775807, 1, -1]
    var sum = 0
    for value in values:
        sum += value
    return sum

def optional_overflow(default: Optional[Int]) -> Int:
    let values = [9223372036854775807]
    var sum = 0
    for value in values:
        sum += values.get(0, default)
    return sum + 1

def effect(var visits: List[Int], value: Int) -> Int:
    visits.append(value)
    return value

def mutated_alias() -> Int:
    let values = [0]
    var alias = values
    alias.set(0, 9223372036854775807)

    var sum = 0
    for value in values:
        sum += value
    return sum + 1

test "closed list scalar summaries preserve sums and lengths":
    filled_sum() | try expect_equal(4950)
    conditional_length(flag: True) | try expect_equal(100)
    conditional_length(flag: False) | try expect_equal(0)

    let empty: List[Int] = []
    var sum = 0
    for value in empty:
        sum += value
    sum | try expect_equal(0)
    empty.length() | try expect_equal(0)

test "closed list reads preserve defaults and evaluation order":
    let values = [10, 20]
    var visits: List[Int] = []
    values.get(default: effect(var visits, 7), index: effect(var visits, 0)) | try expect_equal(
        10
    )
    values.get(-1, effect(var visits, 8)) | try expect_equal(20)
    values.get(3, effect(var visits, 9)) | try expect_equal(9)
    visits | try expect_equal([7, 0, 8, 9])

test "recursive appends keep overflow checks":
    (try expect_fault(lambda: let ignored = self_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = peer_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "list prefixes and Optional defaults keep overflow checks":
    (try expect_fault(lambda: let ignored = prefix_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = optional_overflow(none))) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = optional_overflow(some(0)))) | try expect_contains(
        "Int overflow;"
    )

test "aliased mutation keeps overflow checks":
    (try expect_fault(lambda: let ignored = mutated_alias())) | try expect_contains(
        "Int overflow;"
    )

test "append during traversal retains initial-length semantics":
    var values = [1, 2, 3]
    var sum = 0

    for value in values:
        sum += value
        values.append(9)

    sum | try expect_equal(6)
    values.length() | try expect_equal(6)

def reordered_default_overflow() -> Int:
    let values = [0]
    var sum = 0
    for value in values:
        sum += values.get(default: 9223372036854775807, index: 2)
    return sum + 1

def scalar_append_overflow() -> Int:
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

def match_length() -> Int:
    var values: List[Int] = []

    let ignored = match some(1):
        case some(n):
            values.append(n)
            n
        case none: 0

    return values.length()

def singleton(var values: List[Int]) -> List[Int]:
    values.append(1)
    return values

def default_length() -> Int:
    var values: List[Int] = []
    let callback = lambda (value: List[Int] = singleton(var values)) -> Int: value.length()
    let ignored = callback()
    return values.length()

test "reordered defaults and scalar append dependencies keep overflow checks":
    (try expect_fault(lambda: let ignored = reordered_default_overflow())) | try expect_contains(
        "Int overflow;"
    )
    (try expect_fault(lambda: let ignored = scalar_append_overflow())) | try expect_contains(
        "Int overflow;"
    )

test "hidden match and default mutations invalidate lengths":
    match_length() | try expect_equal(1)
    default_length() | try expect_equal(1)

def literal_length_sum() -> Int:
    let values = [1, 2, 3]
    var sum = 0
    var i = 0

    while i < 321:
        sum += values.length()
        i += 1

    return sum

test "constant length keeps its local valid through partial polling chunks":
    literal_length_sum() | try expect_equal(963)
