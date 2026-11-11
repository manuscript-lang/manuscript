import (
	PromiseOptions,
	complete,
	deferred,
	promise,
	wait_first from "@std/concurrency/promise.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",
	milliseconds, monotonic, sleep from "@std/time.ms",
)

fn immediate(id: Int) Unit:
	complete[Int](id, ok(1))

fn delayed(id: Int) Unit:
	_ := sleep(milliseconds(5000)).wait()
	complete[Int](id, ok(1))

test "wait_first prefers an already completed input over unstarted deferred work":
	pending := deferred[Int](immediate)
	ready := promise(fn: ok(2))
	while not ready.done():
		_ := sleep(milliseconds(1)).wait()
	expect_equal((wait_first([pending, ready])?), 2)?

test "wait_first propagates a deferred promise construction limit":
	pending := deferred[Int](delayed).with(
		options: PromiseOptions(timeout: milliseconds(20))
	)
	start := monotonic()
	reason := wait_first([pending]) | expect_error?
	expect_equal(reason.kind, "ETIMEDOUT")?
	expect_true(monotonic().difference(start).to_milliseconds() < 2000)?
