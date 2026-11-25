// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
)

type Failure {
	message_text String
}

fn success() Int?! {
	return ok(7)
}

fn failure() Int!Failure {
	return error(Failure("failed"))
}

fn propagated() Int!Failure {
	return ok(failure()?)
}

test "prelude cases and optional methods need no imports" {
	inferred Int? := 3
	absent Int? := null
	qualified Int? := 5
	expect_false((inferred == null) or (absent != null))?
	expect_false(
		(inferred or panic("called Optional.get() on null")) != 3 or (
			qualified
			or panic("called Optional.get() on null")
		) != 5
	)?
	expect_false(((absent or 9) != 9 or (absent or 11) != 11))?

	value := success()?
	expect_equal(value or panic("called Optional.get() on null"), 7)?
}

test "try forwards an error of the same type unchanged" {
	outcome := propagated()
	expect_false(not outcome.is_error())?
	expect_equal(outcome.err().message_text, "failed")?
}

test "Error is a record with a message, a kind and details" {
	plain := Error("failed")
	expect_equal(plain.message, "failed")?
	expect_equal(plain.kind, null)?
	expect_equal(plain.details.length(), 0)?

	detailed := Error("no such file", kind: "ENOENT", details: {"path": "/tmp/x"})
	expect_equal(detailed.kind, "ENOENT")?
	expect_equal(detailed.details["path"], "/tmp/x")?
}
