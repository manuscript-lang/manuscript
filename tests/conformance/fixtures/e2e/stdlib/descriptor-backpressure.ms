// conform: tags=testing,tier-io
// conform: phase=test
import (
	spawn from "@std/os/process.ms",
	expect_equal, expect_ok, expect_true from "@std/test/test.ms",
	milliseconds, monotonic from "@std/time.ms",
)

// The child reads nothing for a second, so a writer that never waited would queue all 8
// MiB and return at once.
test "a descriptor write waits while the reader is slow":
	child := spawn("sh", ["-c", "sleep 1; wc -c | tr -d ' '"])?
	chunk := ("x".repeat(1024 * 1024) | expect_ok?).to_bytes()
	var input = child.stdin()
	started := monotonic()
	for index in 0..8:
		input.write(chunk.clone())?

	waited := monotonic().difference(started)
	expect_true(waited.compare(milliseconds(500)) > 0)?
	input.close()?

	count := child.stdout().next()?
	expect_equal(count.get("".to_bytes()), "8388608\n".to_bytes())?
