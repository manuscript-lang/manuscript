import (
    expect_close,
    expect_contains,
    expect_equal,
    expect_error,
    expect_false,
    expect_fault,
    expect_none,
    expect_not_equal,
    expect_ok,
    expect_some,
    expect_true,
    fail
) from "@std/test/test.ms"

fn identity[T](value: T) T:
    return value

test "testing assertions":
    true | try expect_true
    false | try expect_false
    identity(3) | try expect_equal(3)
    "hello" | try expect_equal("hello")
    [1, 2] | try expect_equal([1, 2])
    1 | try expect_not_equal(2)
    try expect_close(1.01, 1.0, 0.02)
    "Manuscript" | try expect_contains("script")

    present: Int? = 7
    absent: Int? = none
    ((present | try expect_some)) | try expect_equal(7)
    absent | try expect_none

    success: Int!Error = ok(9)
    failure: Int!Error = error(Error("bad"))
    ((success | try expect_ok)) | try expect_equal(9)
    ((failure | try expect_error)) | try expect_equal(Error("bad"))

    mismatch := expect_equal(1, 2)
    mismatch_cause := (mismatch | try expect_error)
    mismatch_cause.message | try expect_contains("expected 2, got 1")

    quiet := expect_fault(fn: unit)
    quiet_cause := (quiet | try expect_error)
    quiet_cause.message | try expect_contains("returned normally")

test "failure helpers return errors":
    failed := fail("custom failure")
    failed_cause := (failed | try expect_error)
    failed_cause.message | try expect_contains("custom failure")

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

test "assertions preserve domain equality":
    Key(id: 1, label: "first") | try expect_equal(Key(id: 1, label: "second"))
    Key(id: 1, label: "first") | try expect_not_equal(Key(id: 2, label: "first"))
