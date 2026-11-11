import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type Resource:
	path: String

fn var Resource.close() Unit!:
	append_file(self.path, "closed,").wait()?

fn observed(value: Resource?) Bool: value.is_some()

fn use_named(path: String) Unit!:
	named := Resource(path.clone())
	expect_equal(observed(named), true)?

	bytes := read_file(path).wait()?
	expect_equal(bytes.decode_utf8().get(""), "")?

// A named resource borrowed through an implicit Optional stays open; its owner closes it once.
test "borrowing through an Optional does not close the named owner":
	directory := temporary("optional-borrow-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	use_named(path.clone())?

	bytes := read_file(path).wait()?
	expect_equal(bytes.decode_utf8().get(""), "closed,")?
