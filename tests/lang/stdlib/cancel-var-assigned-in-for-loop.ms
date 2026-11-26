// conform: tags=testing,tier-io
// conform: phase=test
import (
	stat from "@std/os/fs.ms",
	expect_true from "@std/test/test.ms",
)

// A `var` assigned a heap value inside a `for` loop stays registered across the park
// after the loop. The loop's cursor entry is discarded just before it, and that discard
// must not pop the entry of the `var`: cancelling at the `stat` would otherwise leak
// its list.
fn assigned_in_loop() Bool {
	var d = List[String]()
	for x in ["a"] {
		d = [x.clone()]
	}
	return stat("/nonexistent/q").is_ok() or d.is_empty()
}

test "a var assigned in a for loop is freed when cancelled after the loop" {
	expect_true(not assigned_in_loop())?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
