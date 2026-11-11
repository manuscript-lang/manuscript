import (
	Bytes from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
	OpenMode, OpenOptions, open, temporary, write_file from "@std/os/fs.ms",
	expect_ok, expect_true from "@std/test/test.ms",
)

// `FileHandle` is a nominal type with `impl Closeable`, so a binding of one owns the file.
fn view_of(path: String) ReadStream[Bytes]!:
	file := open(path, OpenMode.Read)?
	return ok(file.reader()?)

test "a file handle binding is closed when its scope ends":
	temporary := temporary("manuscript-owned-") | expect_ok?
	path := "{temporary.path()}/a.txt"
	expect_true(write_file(path, "x", true).wait().is_ok())?

	var view = view_of(path) | expect_ok?
	expect_true(view.next().is_ok())?

test "closing a file handle by hand is allowed once more at scope end":
	temporary := temporary("manuscript-owned-") | expect_ok?
	path := "{temporary.path()}/b.txt"
	var file = open(path, OpenMode.Write, OpenOptions(permissions: 420)) | expect_ok?
	expect_true(file.write("hello").is_ok())?
	file.close()?
