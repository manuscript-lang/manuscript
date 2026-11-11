import (
	Bytes from "@std/bytes.ms",
	read_all from "@std/io/streams.ms",
	GlobOptions,
	OpenMode,
	OpenOptions,
	PathEntry,
	Seek,
	copy,
	create_directory,
	glob,
	list,
	open,
	read_file,
	remove,
	rename,
	stat,
	temporary,
	write_file from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok, fail from "@std/test/test.ms",
)

fn expect_fs_error[T](outcome: T!, expected: Error) Unit!:
	match outcome:
		ok(_): return error(Error("filesystem misuse succeeded"))
		error(cause):
			// A failure names the path after the status words: "filesystem: <failure>: <path>".
			named := cause.message.starts_with("{expected.message}: ")
			if (
				cause.kind != expected.kind
				or (cause.message != expected.message and not named)
			): return error(Error("wrong filesystem error: {cause}"))

test "glob queries reuse patterns without changing hidden paths limits or callbacks":
	temporary := temporary("manuscript-glob-") | expect_ok?
	root := temporary.path()
	create_directory(path: "{root}/sub", recursive: false) | expect_ok?
	for name in ["a.txt", "b.md", ".hidden.txt", "sub/c.txt"]:
		write_file(path: "{root}/{name}", data: "", replace: false).wait() | expect_ok?

	all := GlobOptions(patterns: ["**/*.\{txt,md\}"])
	matches := glob(path: root, options: all.clone()) | expect_ok?
	matches.map(fn e: e.path.clone()) | expect_equal(["a.txt", "b.md", "sub/c.txt"])?
	glob(
		path: root, options: GlobOptions(patterns: ["**/*.\{txt,md\}"], max_results: 2)
	) | expect_fs_error(Error("filesystem: limit exceeded", kind: "EOVERFLOW"))?
	glob(path: root, options: GlobOptions(patterns: ["\{a.txt,[\}"])) | expect_fs_error(
		Error("filesystem: invalid input", kind: "EINVAL")
	)?

	options := GlobOptions(patterns: ["*.txt"], exclude: ["sub/**"])
	entries := (
		expect_ok(
			glob(
				path: root, options: options.clone(),
				exclude: fn(entry: PathEntry) Bool: entry.path == "missing.txt"
			)
		)?
	)
	entries.length() | expect_equal(1)?
	entries.get(0).path | expect_equal("a.txt")?
	options.patterns | expect_equal(["*.txt"])?

test "ordinary filesystem misuse retains typed cases":
	temporary := temporary("manuscript-errors-") | expect_ok?
	directory := "{temporary.path()}/directory"
	file := "{temporary.path()}/file"
	_created := create_directory(path: directory, recursive: false) | expect_ok?
	_child := write_file(path: "{directory}/child", data: "x", replace: false).wait() | expect_ok?
	_written := write_file(path: file, data: "abc", replace: false).wait() | expect_ok?
	remove(path: directory, recursive: false) | expect_fs_error(
		Error("filesystem: directory not empty", kind: "ENOTEMPTY")
	)?
	list(path: file) | expect_fs_error(
		Error("filesystem: invalid input", kind: "EINVAL")
	)?
	read_file(path: directory).wait() | expect_fs_error(
		Error("filesystem: invalid input", kind: "EINVAL")
	)?
	create_directory(path: file, recursive: false) | expect_fs_error(
		Error("filesystem: already exists", kind: "EEXIST")
	)?

	var reader = open(file, OpenMode.Read, OpenOptions(permissions: 384)) | expect_ok?
	reader.write("x") | expect_fs_error(Error("I/O: invalid input", kind: "EINVAL"))?
	reader.seek(
		offset: -1, origin: Seek.Start
	) | expect_fs_error(Error("filesystem: invalid input", kind: "EINVAL"))?
	reader.close()?

	writer := open(file, OpenMode.Append, OpenOptions(permissions: 384)) | expect_ok?
	writer.read(1) | expect_fs_error(Error("I/O: invalid input", kind: "EINVAL"))?
	writer.read_file() | expect_fs_error(
		Error("filesystem: invalid input", kind: "EINVAL")
	)?

test "filesystem scoped temporary directories and bounded file reads":
	var directory = ""
	var temporary = temporary("manuscript-stdlib-") | expect_ok?
	directory = temporary.path()

	path := "{directory}/data.txt"
	_written := write_file(path: path, data: "hello", replace: false).wait() | expect_ok?
	read_file(path: path, max_bytes: 5).wait() | expect_ok? | expect_equal(
		"hello".to_bytes()
	)?
	read_file(path: path, max_bytes: 4).wait() | expect_fs_error(
		Error("filesystem: limit exceeded", kind: "EOVERFLOW")
	)?
	write_file(path: path, data: "changed", replace: false).wait() | expect_fs_error(
		Error("filesystem: already exists", kind: "EEXIST")
	)?
	(stat(path: path) | expect_ok?).size | expect_equal(5)?
	(list(path: directory) | expect_ok?).length() | expect_equal(1)?

	opened := open(path, OpenMode.Read) | expect_ok?
	var input = opened.reader() | expect_ok?
	(input.next() | expect_ok?).get() | expect_equal("hello".to_bytes())?
	temporary.close()?
	stat(path: directory) | expect_fs_error(
		Error("filesystem: file or directory not found", kind: "ENOENT")
	)?

test "file handles positional I/O stream adapters and closed errors":
	temporary := temporary("manuscript-handles-") | expect_ok?
	path := "{temporary.path()}/data.txt"
	_written := write_file(path: path, data: "abcdef", replace: false).wait() | expect_ok?
	var handle = open(path, OpenMode.ReadWrite, OpenOptions(permissions: 384)) | expect_ok?
	handle.read_at(offset: 2, max_bytes: 2) | expect_ok? | expect_equal("cd".to_bytes())?
	handle.write_at(offset: 1, data: "XY") | expect_ok?

	_resized := handle.truncate(4) | expect_ok?
	(handle.stat() | expect_ok?).size | expect_equal(4)?

	_sought := handle.seek(offset: 0, origin: Seek.Start) | expect_ok?
	contents := read_all(input: handle.reader()?, max_bytes: none) | expect_ok?
	contents | expect_equal("aXYd".to_bytes())?
	handle.close()?

	closed: Bytes! := error(Error("filesystem: resource is closed", kind: "EBADF"))
	handle.read_at(offset: 0, max_bytes: 1) | expect_equal(closed)?
	handle.close()?

test "empty paths are rejected instead of resolving to the working directory":
	invalid: Unit! := error(cause: Error("filesystem: invalid input", kind: "EINVAL"))
	remove(path: "", recursive: true) | expect_equal(invalid)?
	create_directory(path: "", recursive: true) | expect_equal(invalid)?
	write_file(path: "", data: "x", replace: true).wait() | expect_equal(invalid)?

	match stat(path: ""):
		ok(_): return fail("stat empty path")
		error(cause):
			expect_equal(cause, Error("filesystem: invalid input", kind: "EINVAL"))?

test "rename and copy failures name source and destination":
	temporary := temporary("manuscript-pair-") | expect_ok?
	root := temporary.path()
	from := "{root}/missing"
	to := "{root}/target"
	expected := "filesystem: file or directory not found: {from} -> {to}"

	match rename(from, to):
		ok(_): return fail("rename of a missing file succeeded")
		error(cause): cause.message | expect_equal(expected)?

	match copy(from, to):
		ok(_): return fail("copy of a missing file succeeded")
		error(cause): cause.message | expect_equal(expected)?
