// conform: tags=testing,tier-io
// conform: phase=test
import promise from "@std/concurrency/promise.ms"
import memory_usage from "@std/os/system.ms"
import expect_ok, expect_true from "@std/test/test.ms"

fn faulting() Int!:
	big := "x".repeat(1000000)
	xs: List[Int] := []
	n := xs[big.length()]
	return ok(big.length() + n)

test "a promise that faults releases the values its frames own":
	before := (memory_usage() | expect_ok?).resident

	for i in 0..60:
		void promise[Int](fn: faulting()).wait()

	// Each leaked fault kept 1 MB, so 60 faults would grow the process by 60 MB.
	grown := (memory_usage() | expect_ok?).resident - before
	expect_true(grown < 20000000)?
