// conform: tags=testing,tier-io
// conform: phase=test
import (
	Promise, promise, wait_any from "@std/concurrency/promise.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

// ms: allow_effect std.clock.sleep
fn after(ms: Int, value: Int) Int!:
	void sleep(milliseconds(ms)).wait()
	return ok(value)

test "wait_any reports the first finisher and leaves the others running":
	slow := promise(fn: after(300, 1))
	fast := promise(fn: after(1, 2))
	promises := [slow, fast]
	which := wait_any(promises)?
	expect_equal(which, 1)?
	expect_true(not promises[0].done())?
	expect_equal(promises[1].wait()?, 2)?
	expect_equal(promises[0].wait()?, 1)?

test "wait_any of nothing is an error":
	none_here := List[Promise[Int]]()
	expect_true(wait_any(none_here).is_error())?
