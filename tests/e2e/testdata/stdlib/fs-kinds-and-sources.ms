import (
	ReadStream from "@std/io/io.ms",
	collect from "@std/io/streams.ms",
	DirectoryEntry,
	FileKind,
	OpenMode,
	Seek,
	append_file,
	create_directory,
	open,
	open_directory,
	read_file,
	stat,
	temporary,
	write_atomic,
	write_file from "@std/os/fs.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
)

test "whole-file writes take text or bytes and complete through promises":
	dir := temporary("manuscript-writable-") | expect_ok?
	root := dir.path()
	write_file("{root}/a.txt", "hello").wait() | expect_ok?
	append_file("{root}/a.txt", " world".to_bytes()).wait() | expect_ok?
	write_atomic("{root}/b.txt", "x").wait() | expect_ok?

	data := read_file("{root}/a.txt").wait() | expect_ok?
	data.decode_utf8().get("") | expect_equal("hello world")?

test "stat reports one closed kind and follows links by default":
	dir := temporary("manuscript-kinds-") | expect_ok?
	root := dir.path()
	write_file("{root}/a.txt", "abc").wait() | expect_ok?
	create_directory("{root}/sub", recursive: false) | expect_ok?

	file := stat("{root}/a.txt") | expect_ok?
	file.kind | expect_equal(FileKind.File)?
	file.is_file() | expect_equal(true)?
	file.size | expect_equal(3)?

	sub := stat("{root}/sub") | expect_ok?
	sub.kind | expect_equal(FileKind.Directory)?
	sub.is_directory() | expect_equal(true)?

test "a directory is a stream source of entries and seek takes an origin":
	dir := temporary("manuscript-source-") | expect_ok?
	root := dir.path()
	write_file("{root}/a.txt", "hello world").wait() | expect_ok?
	write_file("{root}/b.txt", "").wait() | expect_ok?

	handle := open("{root}/a.txt", OpenMode.Read) | expect_ok?
	(handle.seek(6, Seek.Start)?) | expect_equal(6)?
	(handle.seek(-1, Seek.End)?) | expect_equal(10)?

	entries := open_directory(root) | expect_ok?
	all := (
		ReadStream[DirectoryEntry](entries)
		| collect(none)
		| expect_ok?
	)
	all.length() | expect_equal(2)?

test "opening a directory classifies invalid and missing paths":
	dir := temporary("manuscript-directory-errors-") | expect_ok?
	root := dir.path()
	file := "{root}/file.txt"
	write_file(file, "hello").wait() | expect_ok?

	invalid := open_directory(file) | expect_error?
	invalid.kind | expect_equal("EINVAL")?
	invalid.message.contains(file) | expect_equal(true)?

	missing := open_directory("{root}/missing") | expect_error?
	missing.kind | expect_equal("ENOENT")?

	child := "{file}/child"
	nested := open_directory(child) | expect_error?
	host_error := stat(child) | expect_error?
	nested.kind | expect_equal(host_error.kind)?

	valid := open_directory(root) | expect_ok?
	valid.path() | expect_equal(root)?
