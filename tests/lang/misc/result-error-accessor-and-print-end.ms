// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn describe(r Int!) String {
	if r.is_error() { return f"failed: {r.err().message}" }
	return "ok"
}

test "err reads the cause of a failure and is_error tells it from a success" {
	failed Int! := error(Error("boom"))
	fine Int! := ok(3)
	expect_equal(describe(failed), "failed: boom")?
	expect_equal(describe(fine), "ok")?
	expect_equal(fine.is_error(), false)?
}

test "print takes an end string" {
	print("a", end: "")
	print("b")
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
