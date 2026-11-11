// conform: tags=control-flow,diagnostics,modules,stdlib-fs,stdlib-testing,testing,tier-io,try-result
// conform: phase=check
// conform: origin=tests/e2e/library_project_test.go:32 TestLibraryProjectCommandsAndCache
import (
	read_file from "@std/os/fs.ms",
	fail from "@std/test/test.ms",

	value from "@lib/value.ms",
)

test "root":
	if value() != 3: return fail("bad value")

	data := read_file(path: "golden/input.txt", max_bytes: 1024).wait()?
	if data.length() != 7: return fail("wrong fixture size")
