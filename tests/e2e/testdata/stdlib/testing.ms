import {
    expect_true,
    expect_false,
    expect_equal,
    expect_not_equal,
    expect_close,
    expect_contains,
    expect_some,
    expect_none,
    expect_ok,
    expect_error,
    expect_fault,
    fail,
    assert_equal
} from "@std/testing.ms"
import panic from "@std/faults.ms"

fn identity[T](value: T) T:
    return value

test "testing assertions":
    try expect_true(true)
    try expect_false(false)
    try expect_equal(identity(3), 3)
    try assert_equal("hello", "hello")
    try expect_equal([1, 2], [1, 2])
    try expect_not_equal(1, 2)
    try expect_close(1.01, 1.0, 0.02)
    try expect_contains("Manuscript", "script")
    let present: Optional[Int] = some(7)
    let absent: Optional[Int] = none
    try expect_equal(try expect_some(present), 7)
    try expect_none(absent)
    let success: Result[Int, String] = ok(9)
    let failure: Result[Int, String] = error("bad")
    try expect_equal(try expect_ok(success), 9)
    try expect_equal(try expect_error(failure), "bad")
    let mismatch_cause = expect_equal(1, 2) | try expect_error
    try expect_contains(mismatch_cause.message(), "expected 2, got 1")
    try expect_contains(try expect_fault(fn(): panic("boom")), "boom")
    let quiet_cause = expect_fault(fn(): unit) | try expect_error
    try expect_contains(quiet_cause.message(), "returned normally")

test "failure helpers return errors":
    let failed_cause = fail("custom failure") | try expect_error
    try expect_contains(failed_cause.message(), "custom failure")

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

test "assertions preserve domain equality":
    try expect_equal(Key(id: 1, label: "first"), Key(id: 1, label: "second"))
    try expect_not_equal(Key(id: 1, label: "first"), Key(id: 2, label: "first"))
