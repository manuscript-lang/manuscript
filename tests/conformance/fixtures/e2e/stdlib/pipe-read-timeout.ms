// conform: tags=testing,tier-io
// conform: phase=test
// conform: timeout=60
import (
	environment from "@std/os/env.ms",
	SpawnOptions, spawn from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	within from "./support/conn.ms",
)

// A read from a child's pipe that waits longer than its timeout fails at the timeout and leaves nothing blocked: the
// test ends at once even though the child, which waits for input, is still running and never wrote.
test "a timed-out read of a child's pipe is cancelled" {
	ms := environment()?.get("MS_UNDER_TEST") or "ms"
	var child = spawn(ms, ["lsp"], SpawnOptions())?
	var output = child.stdout()
	waited := within(output, 1.seconds())
	expect_true(waited.is_error())?
	var input = child.stdin()
	input.close()?
	expect_equal(child.wait(timeout: 20.seconds())?, 0)?
}
