import Closeable from "@std/core.ms"
import TextError from "@std/core.ms"
import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

fn checked(n: Int) Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

fn wrapped(n: Int) Result[Int, TextError]:
    let value = try checked(n)
    return ok(value)

fn total(positive: Bool) Int:
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

fn prefix() Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 2:
        if let found = wrapped(i):
            sum += found
            sum -= found

        i += 1

    return sum

fn peer() Int:
    var sum = 9223372036854775807
    var value = 0
    var i = 0

    while i < 2:
        if let found = checked(value):
            sum += found
        value += 1
        i += 1

    return sum

fn hidden(n: Int) Result[Int, TextError]:
    if n < 0:
        return error(
            TextError(
                match some(n):
                    some(value):
                        return ok(9223372036854775807)
                    none: "negative"
            )
        )

    return ok(n + 1)

fn hidden_success() Int:
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
    var fn close() Unit:
        self.visits.append(7)

fn cleanup(visits: List[Int]) Int:
    with resource = BoundedResultCleanup(visits):
        return total(true)

fn argument(value: Int, var visits: List[Int]) Int:
    visits.append(value)
    return value

fn ordered(var visits: List[Int]) Int:
    var sum = 0
    var i = -1

    while i < 2:
        if let found = wrapped(argument(i, var visits)):
            sum += found
        i += 1

    return sum

test "bounded successful Results preserve both branch budgets":
    total(true) | try expect_equal(expected: 500498)
    total(false) | try expect_equal(expected: -500502)

test "Result payload bounds retain intermediate overflow":
    (try expect_fault(fn(): let ignored = prefix())) | try expect_contains(
        expected: "Int overflow"
    )
    (try expect_fault(fn(): let ignored = peer())) | try expect_contains(
        expected: "Int overflow"
    )

test "Result helper overflow still occurs in the original call":
    (try expect_fault(fn(): let ignored = checked(9223372036854775807))) | try expect_contains(
        expected: "Int overflow"
    )

test "hidden successful returns in error construction keep checks":
    (try expect_fault(fn(): let ignored = hidden_success())) | try expect_contains(
        expected: "Int overflow"
    )

test "Result bounds preserve argument effects and cleanup":
    var visits: List[Int] = []
    ordered(var visits) | try expect_equal(expected: 3)
    visits | try expect_equal(expected: [-1, 0, 1])
    cleanup(visits) | try expect_equal(expected: 500498)
