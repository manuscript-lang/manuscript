// conform: tags=try-result,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn check(n Int) Void! {
	if n < 0 { return }
	return ok()
}

fn forward(n Int) Void! {
	check(n)?
	return ok()
}

test "ok() succeeds with nothing" {
	expect_equal(check(1).is_ok(), true)?
	expect_equal(check(-1).is_ok(), true)?
	expect_equal(forward(2).is_ok(), true)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
