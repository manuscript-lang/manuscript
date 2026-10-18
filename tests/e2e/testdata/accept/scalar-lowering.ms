import {expect_equal, expect_false, expect_not_equal, expect_true} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"

type Counter:
    value: Int = 0

type Resource:
    counter: Counter

impl Closeable for Resource:
    fn close() -> Unit:
        self.counter.value = self.counter.value + 1

fn mark(counter: Counter, digit: Int) -> Int:
    counter.value = counter.value * 10 + digit
    return digit

fn generic[T: Equal](left: T, right: T) -> Bool: left == right

fn returning_match() -> Bool:
    return true == match some(1):
        some(value): return false
        none: false

test "primitive equality captures operands once in order":
    let counter = Counter()
    mark(counter, digit: 1) | try expect_not_equal(expected: mark(counter, digit: 2))
    counter.value | try expect_equal(expected: 12)
    var original = 1
    let captured = original == match some(1):
        some(value):
            original = 2
            value
        none: 0
    (not captured or original != 2) | try expect_false
    let skipped = false and mark(counter, digit: 3) == 3
    let skipped_again = true or mark(counter, digit: 4) == 4
    (skipped or not skipped_again or counter.value != 12) | try expect_false
    ("é" == "e\u{0301}" or "λ🙂" != "λ🙂") | try expect_false
    (generic(left: true, right: true)) | try expect_true
    returning_match() | try expect_false

fn conditional(counter: Counter, take: Bool) -> Int:
    if take:
        with resource = Resource(counter): return 7
    return 8

fn matched(counter: Counter) -> Int:
    return match some(1):
        some(value):
            with resource = Resource(counter): return value
            0
        none: 0

fn defaulted(
    counter: Counter,
    value: Int = match some(2):
        some(number):
            with resource = Resource(counter):
                let used = unit
            number
        none: 0
) -> Int: value

fn nested(counter: Counter) -> Unit:
    let callback = fn() -> Unit:
        with resource = Resource(counter): return
    callback()

fn failed() -> Result[Int, String]: error("expected")

fn propagate(counter: Counter) -> Result[Int, String]:
    with resource = Resource(counter):
        let value = try failed()
        return ok(value)

    return ok(0)

fn bare_propagate() -> Result[Int, String]:
    let value = try failed()
    return ok(value)

fn equality_propagate() -> Result[Bool, String]:
    let matches = (try failed()) == 0
    return ok(matches)

fn bool_failed() -> Result[Bool, String]: error("expected")

fn nested_results(counter: Counter) -> Result[Int, String]:
    let child = fn() -> Result[Bool, String]:
        with resource = Resource(counter):
            let value = try bool_failed()
            return ok(value)

        return ok(false)
    let ignored = child()
    let value = try failed()
    return ok(value)

fn statement_match_try(counter: Counter) -> Result[Int, String]:
    match some(1):
        some(number):
            with resource = Resource(counter):
                let value = try failed()
                return ok(value)
        none: return ok(0)

    return ok(-1)

fn value_match_loop_try(counter: Counter) -> Result[Int, String]:
    var index = 0

    while index < 2:
        let selected = match some(index):
            some(number):
                with resource = Resource(counter):
                    let value = try failed()
                    let used = value
                number
            none: 0

        index = index + 1

    return ok(index)

test "combined lowering retains callable state and try boundaries":
    let counter = Counter()
    (
        (
            nested_results(counter) != Result[Int, String].error("expected")
            or counter.value != 1
        )
    ) | try expect_false
    (
        (
            statement_match_try(counter) != Result[Int, String].error(
                "expected"
            )
            or counter.value != 2
        )
    ) | try expect_false
    (
        (
            value_match_loop_try(counter) != Result[Int, String].error(
                "expected"
            )
            or counter.value != 3
        )
    ) | try expect_false

test "cleanup remains owned by its source callable":
    let counter = Counter()
    (conditional(counter, take: false) != 8 or counter.value != 0) | try expect_false
    (conditional(counter, take: true) != 7 or counter.value != 1) | try expect_false
    (matched(counter) != 1 or counter.value != 2) | try expect_false
    (defaulted(counter) != 2 or counter.value != 3) | try expect_false
    (defaulted(counter, value: 9) != 9 or counter.value != 3) | try expect_false
    nested(counter)
    counter.value | try expect_equal(expected: 4)
    (
        (
            propagate(counter) != Result[Int, String].error("expected")
            or counter.value != 5
        )
    ) | try expect_false
    bare_propagate() | try expect_equal(expected: Result[Int, String].error("expected"))
    equality_propagate() | try expect_equal(
        expected: Result[Bool, String].error("expected")
    )
    var index = 0

    while index < 3:
        index = index + 1

        with resource = Resource(counter):
            if index == 1: continue
            if index == 2: break

    counter.value | try expect_equal(expected: 7)
