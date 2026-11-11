import (
	OpenMode, OpenOptions, open, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// `clone` copies a resource: each copy owns its own descriptor and closes on its own. A `Connection` has no clone: its
// `input` and `output` streams are the two owners (see net.ms).

test "a cloned file handle writes through its own descriptor after the original closes":
	temporary := temporary("manuscript-dup-") | expect_ok?
	path := "{temporary.path()}/a.txt"
	var file = open(path, OpenMode.Write, OpenOptions(permissions: 420)) | expect_ok?
	var copy = file.clone() | expect_ok?
	file.write("one ")?
	file.close()?
	copy.write("two")?
	copy.close()?
	expect_equal(read_file(path).wait()?, "one two".to_bytes())?
