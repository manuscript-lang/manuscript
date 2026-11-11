import (
	open_directory, stat, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms",
)

// `Directory` and `TemporaryDirectory` are nominal types with `impl Closeable`, so a binding owns them.
fn leaves_a_temporary() String!:
	temporary := temporary("manuscript-owned-")?
	path := temporary.path()
	write_file("{path}/a.txt", "x", true).wait()?
	return ok(path)

test "a temporary directory binding is removed when its scope ends":
	path := leaves_a_temporary() | expect_ok?
	expect_false(stat(path).is_ok())?

fn counts_entries(path: String) Int!:
	cursor := open_directory(path)?
	var seen = 0

	while true:
		next := cursor.read()?
		if next.is_none(): break

		seen += 1

	return ok(seen)

test "a directory cursor reads its children and closes at scope end":
	temporary := temporary("manuscript-owned-") | expect_ok?
	path := temporary.path()
	expect_true(write_file("{path}/a.txt", "x", true).wait().is_ok())?
	expect_true(write_file("{path}/b.txt", "y", true).wait().is_ok())?
	counts_entries(path) | expect_ok? | expect_equal(2)?
