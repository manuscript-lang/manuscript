# conform: tags=aliasing,closures,control-flow,generics,interfaces,interpolation,match,modules,mutation,optional,records,stdlib-cleanup,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/scalar-lowering.ms
import TextError from "@std/core.ms"
import expect_equal, expect_false, expect_not_equal from "@std/test.ms"
import Closeable from "@std/core.ms"

type Counter:
    value: Int = 0

type Resource:
    counter: Counter

impl Closeable for Resource:
    var fn close() Unit:
        self.counter.value += 1

fn mark(var counter: Counter, digit: Int) Int:
    counter.value = counter.value * 10 + digit
    return digit

fn generic[T: Equal](left: T, right: T) Bool: left == right

fn returning_match() Bool:
    return true == match 1:
        _value: return false
        none: false

test "primitive equality captures operands once in order":
    var counter = Counter()
    try expect_not_equal(mark(var counter, 1), mark(var counter, 2))
    try expect_equal(counter.value, 12)

    var original = 1
    let captured = original == match 1:
        value:
            original = 2
            value
        none: 0
    try expect_false(not captured or original != 2)

    let skipped = false and mark(var counter, 3) == 3
    let skipped_again = true or mark(var counter, 4) == 4
    try expect_false((skipped or not skipped_again or counter.value != 12))
    try expect_false("é" == "e\u{0301}" or "λ🙂" != "λ🙂")
    try expect_false(not generic(left: true, right: true))
    try expect_false(returning_match())

fn conditional(counter: Counter, take: Bool) Int:
    if take:
        let _resource = Resource(counter)
        return 7

    return 8

fn matched(counter: Counter) Int:
    return match 1:
        value:
            var _resource = Resource(counter)
            return value
            0
        none: 0

fn defaulted(
    counter: Counter,
    value: Int = match 2:
        number:
            var _resource = Resource(counter)
            let _used = unit
            _resource.close()
            number
        none: 0
) Int: value

fn nested(counter: Counter) Unit:
    let callback = fn() Unit:
        let _resource = Resource(counter)
        return

    callback()

fn failed() Int!TextError: error(TextError("expected"))

fn propagate(counter: Counter) Int!TextError:
    var _resource = Resource(counter)
    let value = try failed()
    return ok(value)
    return ok(0)

fn bare_propagate() Int!TextError:
    let value = try failed()
    return ok(value)

fn equality_propagate() Bool!TextError:
    let matches = (try failed()) == 0
    return ok(matches)

fn bool_failed() Bool!TextError: error(TextError("expected"))

fn nested_results(counter: Counter) Int!TextError:
    let child = fn() Bool!TextError:
        var _resource = Resource(counter)
        let value = try bool_failed()
        return ok(value)
        return ok(false)

    let _ignored = child()
    let value = try failed()
    return ok(value)

fn statement_match_try(counter: Counter) Int!TextError:
    match present(1):
        _value:
            let _resource = Resource(counter)
            let value = try failed()
            return ok(value)
        none: return ok(0)

    return ok(-1)

fn value_match_loop_try(counter: Counter) Int!TextError:
    var index = 0

    while index < 2:
        let _selected = match index:
            number:
                var _resource = Resource(counter)
                let _value = try failed()
                _resource.close()
                number
            none: 0

        index += 1

    return ok(index)

test "combined lowering retains callable state and try boundaries":
    let counter = Counter()
    try expect_false(
        (
            nested_results(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 1
        )
    )
    try expect_false(
        (
            statement_match_try(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 2
        )
    )
    try expect_false(
        (
            value_match_loop_try(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 3
        )
    )

test "cleanup remains owned by its source callable":
    let counter = Counter()
    try expect_false(conditional(counter, take: false) != 8 or counter.value != 0)
    try expect_false(conditional(counter, take: true) != 7 or counter.value != 1)
    try expect_false(matched(counter) != 1 or counter.value != 2)
    try expect_false(defaulted(counter) != 2 or counter.value != 3)
    try expect_false(defaulted(counter, 9) != 9 or counter.value != 3)
    nested(counter)
    try expect_equal(counter.value, 4)
    try expect_false(
        (
            propagate(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 5
        )
    )
    try expect_equal(
        bare_propagate(), Result[Int, TextError].error(TextError("expected"))
    )
    try expect_equal(
        equality_propagate(), Result[Bool, TextError].error(TextError("expected"))
    )

    var index = 0

    while index < 3:
        index += 1

        let _resource = Resource(counter)
        if index == 1: continue
        if index == 2: break

    try expect_equal(counter.value, 7)

fn present[T](value: T) T?:
    return value
