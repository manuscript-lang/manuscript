// conform: tags=control-flow,tier-core
// conform: phase=test
import expect_equal, fail from "@std/test/test.ms"

fn check() Bool! {
	return ok(true)
}

// A line that starts with `(` after a match block's closing brace is a statement of its own: the block ends the
// previous statement, so the parenthesis is not a call of the match.
test "a parenthesized statement after a match block is not a call" {
	match check() {
		ok(_) => {
			_checked := void
		}
		error(_) => {
			return fail(message: "check failed")
		}
	}
	("abc").length() | expect_equal(3)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
