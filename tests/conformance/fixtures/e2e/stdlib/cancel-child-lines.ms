// conform: tags=testing,tier-io
// conform: phase=test
import (
	collect, lines from "@std/io/streams.ms",
	spawn from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
)

test "lines over a child's stdout with temporaries":
	child := spawn("sh", ["-c", "printf 'a\\nbb\\nccc\\n'; sleep 0.05"])?
	got := collect(lines(child.stdout()), none)?
	expect_equal(got.length(), 3)?
