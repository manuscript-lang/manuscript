// conform: tags=try-result,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn check(n Int) Void!:
	if n < 0: return
	return ok()

test "bare return in a Void! function is ok(unit)":
	expect_equal(check(-1).is_ok(), true)?
	expect_equal(check(1).is_ok(), true)?
