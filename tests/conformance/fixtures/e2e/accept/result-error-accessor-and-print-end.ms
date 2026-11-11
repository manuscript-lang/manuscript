// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn describe(r: Int!) String:
	if bad := r.error(): return "failed: {bad.message}"
	return "ok"

test "error is some for a failure and none for a success":
	failed: Int! := error(Error("boom"))
	fine: Int! := ok(3)
	expect_equal(describe(failed), "failed: boom")?
	expect_equal(describe(fine), "ok")?
	expect_equal(fine.error().is_none(), true)?

test "print takes an end string":
	print("a", end: "")
	print("b")
