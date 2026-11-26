// conform: tags=testing,tier-io
// conform: phase=test
import (
	memory_usage from "@std/os/system.ms",
	expect_ok from "@std/test/test.ms",
	sleep from "@std/time.ms",
)

// A promise made and waited on in one expression has no name, so the statement that
// ends it closes it; each unclosed promise kept its table row.
test "an unnamed promise waited on in place is closed" {
	for i in 0..100 {
		void sleep(1.milliseconds()).wait()
	}

	before := (memory_usage() | expect_ok?).heap_used
	for i in 0..3000 {
		void sleep(1.milliseconds()).wait()
	}

	grown := (memory_usage() | expect_ok?).heap_used - before
	if grown > 2000000 { return error(Error(f"heap grew {grown} bytes over 3000 waits")) }
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
