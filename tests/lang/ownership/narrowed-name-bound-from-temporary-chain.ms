// conform: tags=ownership,scope-cleanup,control-flow,tier-core,testing
// conform: phase=test
import (
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// A name bound from a call chain whose temporary closes with the statement, and narrowed by the
// `if` that follows, belongs to the scope outside the statement. It used to be registered in the
// statement's own scope, so the value was released when the statement ended and read afterwards.
fn read_text(path String) String {
	data := read_file(path).wait().to_optional()
	if data != null { return (data.decode_utf8() or "") }

	return ""
}

test "a narrowed name bound from a temporary chain outlives its statement" {
	dir := temporary("ms-narrowed-bind-") | expect_ok?
	path := f"{dir.path()}/note.txt"
	write_file(path, "kept after the statement", replace: true).wait()?
	expect_equal(read_text(path), "kept after the statement")?
	expect_equal(read_text(f"{dir.path()}/missing.txt"), "")?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
