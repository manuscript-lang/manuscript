// conform: tags=testing,tier-io
// conform: phase=test
// A thread that waits on a timer keeps answering it while a promise it started computes: an idle
// thread starts its own promise at once only when nothing on it waits for a clock or a descriptor
// (see `own_ready` in the scheduler), so a sleeping main is not held late by that work.
import (
	Promise, promise from "@std/concurrency/promise.ms",
	sleep from "@std/time.ms",
	expect_true from "@std/test/test.ms",
)

fn burn(rounds: Int) Int!:
	var x = 1
	for i in 0..rounds:
		x = (x * 31 + i) % 1000003
	return ok(x)

test "a sleeping main wakes on time while a promise it started computes":
	work := promise[Int](fn: burn(40000000))
	for round in 0..5:
		void sleep(1.milliseconds()).wait()
	expect_true(not work.done())?
	void work.wait()
