from "@std/core.ms" import Closeable
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_contains, expect_equal, expect_fault

def checked(n: Int) -> Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

def wrapped(n: Int) -> Result[Int, TextError]:
    let value = try checked(n)
    return ok(value)

def total(positive: Bool) -> Int:
    var sum = 0
    var i = -2

    while i < 1000:
        if let found = wrapped(i):
            if positive:
                sum += found
            else:
                sum -= found
        else:
            sum -= 1

        i += 1

    return sum

def prefix() -> Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 2:
        if let found = wrapped(i):
            sum += found
            sum -= found

        i += 1

    return sum

def peer() -> Int:
    var sum = 9223372036854775807
    var value = 0
    var i = 0

    while i < 2:
        if let found = checked(value):
            sum += found
        value += 1
        i += 1

    return sum

def hidden(n: Int) -> Result[Int, TextError]:
    if n < 0:
        return error(
            TextError(
                match some(n):
                    case some(value):
                        return ok(9223372036854775807)
                    case none: "negative"
            )
        )

    return ok(n + 1)

def hidden_success() -> Int:
    var sum = 1
    var i = -1

    while i < 1:
        if let found = hidden(i):
            sum += found
        i += 1

    return sum

type BoundedResultCleanup:
    visits: List[Int]

impl Closeable for BoundedResultCleanup:
    var def close() -> Unit:
        self.visits.append(7)

def cleanup(visits: List[Int]) -> Int:
    with let resource = BoundedResultCleanup(visits):
        return total(True)

def argument(value: Int, var visits: List[Int]) -> Int:
    visits.append(value)
    return value

def ordered(var visits: List[Int]) -> Int:
    var sum = 0
    var i = -1

    while i < 2:
        if let found = wrapped(argument(i, var visits)):
            sum += found
        i += 1

    return sum

test "bounded successful Results preserve both branch budgets":
    total(True) | try expect_equal(500498)
    total(False) | try expect_equal(-500502)

test "Result payload bounds retain intermediate overflow":
    (try expect_fault(lambda: let ignored = prefix())) | try expect_contains(
        "Int overflow"
    )
    (try expect_fault(lambda: let ignored = peer())) | try expect_contains(
        "Int overflow"
    )

test "Result helper overflow still occurs in the original call":
    (try expect_fault(lambda: let ignored = checked(9223372036854775807))) | try expect_contains(
        "Int overflow"
    )

test "hidden successful returns in error construction keep checks":
    (try expect_fault(lambda: let ignored = hidden_success())) | try expect_contains(
        "Int overflow"
    )

test "Result bounds preserve argument effects and cleanup":
    var visits: List[Int] = []
    ordered(var visits) | try expect_equal(3)
    visits | try expect_equal([-1, 0, 1])
    cleanup(visits) | try expect_equal(500498)
