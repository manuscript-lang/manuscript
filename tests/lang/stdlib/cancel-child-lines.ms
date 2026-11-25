// conform: tags=testing,tier-io
// conform: phase=test
import (
	lines from "@std/io/steps.ms",
	collect from "@std/io/streams.ms",
	spawn from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
)

test "lines over a child's stdout with temporaries" {
	child := spawn("sh", ["-c", "printf 'a\\nbb\\nccc\\n'; sleep 0.05"])?
	got := collect(lines(child.stdout()), null)?
	expect_equal(got.length(), 3)?
}
