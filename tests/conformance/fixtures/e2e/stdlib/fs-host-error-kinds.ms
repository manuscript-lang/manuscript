// conform: tags=testing,tier-io
// conform: phase=test
import (
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
)

test "a file name past the host limit reports ENAMETOOLONG on every platform" {
	dir := temporary("manuscript-longname-") | expect_ok?
	path := f"{dir.path()}/{"a".repeat(300)}"
	read := expect_error(read_file(path).wait())?
	expect_equal(read.kind, "ENAMETOOLONG")?
	expect_equal(read.message.starts_with("filesystem: file name too long"), true)?

	written := expect_error(write_file(path, "x").wait())?
	expect_equal(written.kind, "ENAMETOOLONG")?
}
