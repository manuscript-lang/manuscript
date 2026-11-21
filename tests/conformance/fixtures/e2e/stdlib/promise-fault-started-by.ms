// conform: tags=testing,tier-stdlib,faults
// conform: phase=test
import (
	Promise, promise from "@std/concurrency/promise.ms",
	expect_true from "@std/test/test.ms",
)

fn index_past_end(n: Int) Int:
	xs := [0]
	return xs[n]

fn start_faulting_work() Promise[Int]:
	return promise(fn() Result[Int, Error]: return ok(index_past_end(3)))

test "a fault in a promise's work names the code that started it":
	message := start_faulting_work().wait().err().message
	expect_true(message.contains("in index_past_end"))?
	started := message.split("task started by:")
	expect_true(started.length() == 2)?
	expect_true(started[1].contains("in start_faulting_work"))?
