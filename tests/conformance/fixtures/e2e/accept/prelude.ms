// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, fail from "@std/test/test.ms"

type Failure:
	message_text: String

fn success() Int?!:
	return ok(7)

fn failure() Int!Failure:
	return error(Failure("failed"))

fn propagated() Int!Failure:
	return ok(failure()?)

test "prelude cases and optional methods need no imports":
	inferred: Int? := 3
	absent: Int? := none
	qualified: Int? := 5
	expect_false(inferred.is_none() or absent.is_some())?
	expect_false(inferred.get() != 3 or qualified.get() != 5)?
	expect_false(
		(absent.get(9) != 9 or absent.or_else(fn() Int?: return 11).get() != 11)
	)?

	value := success()?
	expect_equal(value.get(), 7)?

test "try forwards an error of the same type unchanged":
	outcome := propagated()
	expect_false(not outcome.is_error())?
	expect_equal(outcome.err().message_text, "failed")?

test "Error is a record with a message, a kind and details":
	plain := Error("failed")
	expect_equal(plain.message, "failed")?
	expect_equal(plain.kind, none)?
	expect_equal(plain.details.length(), 0)?

	detailed := Error("no such file", kind: "ENOENT", details: {"path": "/tmp/x"})
	expect_equal(detailed.kind, "ENOENT")?
	expect_equal(detailed.details["path"], "/tmp/x")?
