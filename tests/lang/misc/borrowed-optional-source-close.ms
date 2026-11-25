// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type Resource {
	path String
}

fn move Resource.close() Void! {
	append_file(self.path, "closed,").wait()?
}

fn observed(value Resource?) Bool => value != null

fn use_named(path String) Void! {
	named := Resource(path.clone())
	expect_equal(observed(named), true)?

	bytes := read_file(path).wait()?
	expect_equal(bytes.decode_utf8() or "", "")?
}

// A named resource borrowed through an implicit Optional stays open; its owner closes
// it once.
test "borrowing through an Optional does not close the named owner" {
	directory := temporary("optional-borrow-")?
	path := f"{directory.path()}/log"
	write_file(path, "").wait()?
	use_named(path.clone())?

	bytes := read_file(path).wait()?
	expect_equal(bytes.decode_utf8() or "", "closed,")?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
