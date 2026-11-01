import TextError from "@std/core.ms"
import (
    expect_equal,
    expect_false,
    expect_not_equal,
    expect_ok,
    expect_true
) from "@std/test/test.ms"
import Closeable from "@std/core.ms"
import read_file, temporary, write_file from "@std/os/fs.ms"

type Counter:
    value: Int = 0

type Resource:
    marker: String

# Cleanup runs on the resource's own copy, so a marker file is how a caller observes it.
impl Closeable for Resource:
    var fn close() Unit!:
        let _written = write_file(self.marker, "closed", true)
        return ok(unit)

fn closed(marker: String) Bool: read_file(marker).is_ok()

fn mark(var counter: Counter, digit: Int) Int:
    counter.value = counter.value * 10 + digit
    return digit

fn generic[T: Equal](left: T, right: T) Bool: left == right

fn returning_match() Bool:
    return true == match present(1):
        _value: return false
        none: false

test "primitive equality captures operands once in order":
    var counter = Counter()
    try expect_not_equal(mark(var counter, 1), mark(var counter, 2))
    try expect_equal(counter.value, 12)

    var original = 1
    let captured = original == match present(1):
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

fn conditional(marker: String, take: Bool) Int:
    if take:
        let _resource = Resource(marker.clone())
        return 7

    return 8

fn matched(marker: String) Int:
    return match present(1):
        value:
            var _resource = Resource(marker.clone())
            return value
            0
        none: 0

fn defaulted(
    marker: String,
    value: Int = match present(2):
        number:
            var _resource = Resource(marker.clone())
            let _used = unit
            _resource.close().get(none)
            number
        none: 0
) Int: value

fn nested(marker: String) Unit:
    let callback = fn() Unit:
        let _resource = Resource(marker.clone())
        return

    callback()

fn failed() Int!TextError: error(TextError("expected"))

fn propagate(marker: String) Int!TextError:
    var _resource = Resource(marker.clone())
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

fn nested_results(marker: String) Int!TextError:
    let child = fn() Bool!TextError:
        var _resource = Resource(marker.clone())
        let value = try bool_failed()
        return ok(value)
        return ok(false)

    let _ignored = child()
    let value = try failed()
    return ok(value)

fn statement_match_try(marker: String) Int!TextError:
    match present(1):
        _value:
            let _resource = Resource(marker.clone())
            let value = try failed()
            return ok(value)
        none: return ok(0)

    return ok(-1)

fn value_match_loop_try(marker: String) Int!TextError:
    var index = 0

    while index < 2:
        let _selected = match present(index):
            number:
                var _resource = Resource(marker.clone())
                let _value = try failed()
                _resource.close().get(none)
                number
            none: 0

        index += 1

    return ok(index)

test "combined lowering retains callable state and try boundaries":
    let temporary = temporary("manuscript-scalar-") | try expect_ok
    let dir = temporary.path()
    let expected = Result[Int, TextError].error(TextError("expected"))
    try expect_equal(nested_results("{dir}/nested"), expected)
    try expect_true(closed("{dir}/nested"))
    try expect_equal(statement_match_try("{dir}/statement"), expected)
    try expect_true(closed("{dir}/statement"))
    try expect_equal(value_match_loop_try("{dir}/loop"), expected)
    try expect_true(closed("{dir}/loop"))

test "cleanup remains owned by its source callable":
    let temporary = temporary("manuscript-scalar-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(conditional("{dir}/skipped", take: false), 8)
    try expect_false(closed("{dir}/skipped"))
    try expect_equal(conditional("{dir}/taken", take: true), 7)
    try expect_true(closed("{dir}/taken"))
    try expect_equal(matched("{dir}/matched"), 1)
    try expect_true(closed("{dir}/matched"))
    try expect_equal(defaulted("{dir}/default"), 2)
    try expect_true(closed("{dir}/default"))
    try expect_equal(defaulted("{dir}/supplied", 9), 9)
    try expect_false(closed("{dir}/supplied"))
    nested("{dir}/nested")
    try expect_true(closed("{dir}/nested"))
    try expect_equal(
        propagate("{dir}/propagated"),
        Result[Int, TextError].error(TextError("expected"))
    )
    try expect_true(closed("{dir}/propagated"))
    try expect_equal(
        bare_propagate(), Result[Int, TextError].error(TextError("expected"))
    )
    try expect_equal(
        equality_propagate(), Result[Bool, TextError].error(TextError("expected"))
    )

    var index = 0

    while index < 3:
        index += 1

        let _resource = Resource("{dir}/loop{index}")
        if index == 1: continue
        if index == 2: break

    try expect_true(closed("{dir}/loop1"))
    try expect_true(closed("{dir}/loop2"))
    try expect_false(closed("{dir}/loop3"))

fn present[T](value: T) T?:
    return value
