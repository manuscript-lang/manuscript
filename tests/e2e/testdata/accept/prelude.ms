import expect_equal, expect_false, fail from "@std/test/test.ms"

type Failure:
    message_text: String

fn success() Int?!:
    return ok(7)

fn failure() Int!Failure:
    return error(Failure("failed"))

fn propagated() Int!Failure:
    return ok(try failure())

test "prelude cases and optional methods need no imports":
    let inferred: Int? = 3
    let absent: Int? = none
    let qualified: Int? = 5
    try expect_false(not inferred.is_some() or not absent.is_none())
    try expect_false(inferred.get() != 3 or qualified.get() != 5)
    try expect_false(
        (absent.get(9) != 9 or absent.or_else(fn() Int?: return 11).get() != 11)
    )

    let value = try success()
    try expect_equal(value.get(), 7)

test "try forwards an error of the same type unchanged":
    let outcome = propagated()
    try expect_false(not outcome.is_error())
    try expect_equal(outcome.err().message_text, "failed")

test "Error is a record with a message, a kind and details":
    let plain = Error("failed")
    try expect_equal(plain.message, "failed")
    try expect_equal(plain.kind, ErrorCategory.Other)
    try expect_equal(plain.details.length(), 0)

    let detailed = Error("no such file", kind: NotFound, details: {"path": "/tmp/x"})
    try expect_equal(detailed.kind, ErrorCategory.NotFound)
    try expect_equal(detailed.details["path"], "/tmp/x")
