// conform: tags=lists,control-flow,scope-cleanup,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A list moved out of one variable into another and back, then into a binding made inside a
// branch: the branch binding owns the list and releases it where the branch ends, and the
// path that skips the branch releases what the outer variable still holds.
fn rebound(c Int) Int:
	var outer = ["a"]
	var carried = outer
	var seen = 0
	if c == 0:
		outer = carried
		var kept = outer
		seen = kept.length()
	return seen

fn rebound_nested(c Int) Int:
	var outer = ["a", "b"]
	var carried = outer
	var seen = 0
	if c > 0:
		if c > 1:
			carried.append("c")
		outer = carried
		var kept = outer
		seen = kept.length()
	else:
		seen = -1
	return seen

test "a list moved into a branch binding is released at the end of the branch":
	expect_equal(rebound(0), 1)?
	expect_equal(rebound(1), 0)?

test "nested branches hand the list on and release it once":
	expect_equal(rebound_nested(0), -1)?
	expect_equal(rebound_nested(1), 2)?
	expect_equal(rebound_nested(2), 3)?
