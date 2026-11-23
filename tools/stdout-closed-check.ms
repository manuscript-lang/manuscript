// A command whose standard output cannot be written must fail
// (`ctest -R stdout_closed`): `ms doc` writes more than a pipe holds, so the child is
// still writing when this program closes the read end, and it must exit nonzero (a
// write error, or SIGPIPE) instead of finishing with status 0. Runs on every platform.
// MS names the ms to run (default .artifacts/build/ci/src/cli/ms). Usage: ms run
// tools/stdout-closed-check.ms
import (
	working_directory from "@std/os/env.ms",
	spawn from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

fn main() Void!:
	ms := tool_ms(working_directory().get().clone())
	child := spawn(ms, ["doc"])?
	var stdout = child.stdout()
	void stdout.next()?
	void stdout.close()?

	status := child.wait(timeout: seconds(60))?

	if status == 0:
		print("ms doc exited 0 after its standard output was closed")
		return error(Error("a write failure on standard output was not reported"))

	return ok(void)
