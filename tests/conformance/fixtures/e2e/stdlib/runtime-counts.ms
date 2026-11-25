// conform: tags=stdlib,testing,tier-stdlib
// conform: phase=test
import (
	runtime_counts from "@std/os/system.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "runtime counts grow with the work a program does" {
	before := runtime_counts()?
	var xs List[Int] = []
	for i in 0..1000 {
		xs.append(i)
	}

	after := runtime_counts()?
	expect_true(after.allocations > before.allocations)?
	expect_true(after.allocated_bytes - before.allocated_bytes >= 8000)?
	expect_equal(xs.length(), 1000)?
}
