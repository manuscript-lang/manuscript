// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	CopyOptions,
	copy,
	create_directory,
	list,
	read_file,
	remove,
	stat,
	temporary,
	write_file from "@std/os/fs.ms",
	expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms",
)

fn expect_limit(outcome: Unit!) Unit!:
	cause := expect_error(outcome)?
	expect_equal(cause.kind, "EOVERFLOW")?
	if not cause.message.starts_with("filesystem: limit exceeded"):
		return error(Error("wrong limit message: {cause.message}"))

fn generic_write(path: String, data: String) Unit!:
	return write_file(path, data).wait()

fn generic_copy(source: String, destination: String) Unit!:
	return copy(source, destination)

fn generic_tree(source: String, destination: String) Unit!:
	return copy(source, destination, CopyOptions(recursive: true))

fn generic_directory(path: String) Unit!:
	return create_directory(path)

fn generic_remove(path: String) Unit!:
	return remove(path)

fn rejected(result: Unit!) Unit!:
	match result:
		error(_): return ok(unit)
		ok(_): return error(Error("exclusive or nonrecursive operation succeeded"))

fn text(path: String) String!:
	return ok((read_file(path).wait() | expect_ok?).decode_utf8().get())

fn argument(var log: List[String], mark: String, path: String) String:
	log.append(mark)
	return path

fn data_argument(var log: List[String]) Bytes:
	log.append("data")
	return "new".to_bytes()

test "filesystem writes default to exclusive creation through aliases and bounds":
	temporary := temporary("manuscript-default-write-") | expect_ok?
	path := "{temporary.path()}/file"
	write_file(path, "first").wait() | expect_ok?

	write := write_file
	alias := write_file
	(rejected(alias(path, "second").wait())?)
	(rejected(write(path, "second", replace: false).wait())?)
	(rejected(generic_write(path, "second"))?)
	(text(path)?) | expect_equal("first")?
	(alias(path, "second", replace: true).wait() | expect_ok?)
	(text(path)?) | expect_equal("second")?
	(generic_write("{temporary.path()}/generic", "generic") | expect_ok?)
	(rejected(write_file("", "invalid").wait())?)

test "filesystem file copies default to no replacement and retain byte limits":
	temporary := temporary("manuscript-default-copy-") | expect_ok?
	source := "{temporary.path()}/source"
	destination := "{temporary.path()}/destination"
	write_file(source, "source").wait() | expect_ok?

	alias := copy
	(alias(source, destination) | expect_ok?)
	write_file(source, "changed", true).wait() | expect_ok?
	(rejected(copy(source, destination))?)
	(rejected(copy(source, destination, CopyOptions(replace: false)))?)
	(rejected(generic_copy(source, destination))?)
	(text(destination)?) | expect_equal("source")?
	(copy(source, destination, CopyOptions(replace: true)) | expect_ok?)
	(text(destination)?) | expect_equal("changed")?
	(generic_copy(source, "{temporary.path()}/generic") | expect_ok?)
	(
		copy(
			source,
			"{temporary.path()}/limited",
			CopyOptions(max_bytes: 0),
		) | expect_limit?
	)
	(
		copy(
			source,
			"{temporary.path()}/limited",
			CopyOptions(max_bytes: 6),
		) | expect_limit?
	)
	(copy(source, "{temporary.path()}/exact", CopyOptions(max_bytes: 7)) | expect_ok?)

test "filesystem tree copies default to no replacement with distinct budgets":
	temporary := temporary("manuscript-default-tree-") | expect_ok?
	source := "{temporary.path()}/source"
	destination := "{temporary.path()}/destination"
	tree := CopyOptions(recursive: true)
	create_directory(source) | expect_ok?
	write_file("{source}/data", "abc").wait() | expect_ok?

	alias := copy
	(alias(source, destination, tree) | expect_ok?)
	write_file("{source}/data", "xyz", true).wait() | expect_ok?
	(rejected(copy(source, destination, tree))?)
	(rejected(copy(source, destination, CopyOptions(recursive: true, replace: false)))?)
	(rejected(generic_tree(source, destination))?)
	(text("{destination}/data")?) | expect_equal("abc")?
	(
		copy(
			source,
			destination,
			CopyOptions(recursive: true, replace: true),
		) | expect_ok?
	)
	(text("{destination}/data")?) | expect_equal("xyz")?
	(generic_tree(source, "{temporary.path()}/generic") | expect_ok?)
	(
		copy(
			source,
			"{temporary.path()}/entries",
			CopyOptions(recursive: true, max_entries: 1),
		) | expect_limit?
	)
	(
		copy(
			source,
			"{temporary.path()}/bytes",
			CopyOptions(recursive: true, max_bytes: 2),
		) | expect_limit?
	)

	invalid: Unit! := error(Error("filesystem: invalid input", kind: "EINVAL"))
	(
		copy(
			source,
			"{temporary.path()}/negative-byte",
			CopyOptions(recursive: true, max_bytes: -1),
		) | expect_equal(invalid)?
	)
	(
		copy(
			source,
			"{temporary.path()}/exact",
			CopyOptions(recursive: true, max_entries: 2, max_bytes: 3),
		) | expect_ok?
	)

test "filesystem tree copies reject empty and disjoint existing directories":
	directory := temporary("manuscript-existing-tree-")?
	source := "{directory.path()}/source"
	destination := "{directory.path()}/destination"
	create_directory(source)?
	create_directory(destination)?

	tree := CopyOptions(recursive: true)
	empty := expect_error(copy(source, destination, tree))?
	expect_equal(empty.kind, "EEXIST")?
	write_file("{source}/new", "new").wait()?
	write_file("{destination}/keep", "keep").wait()?

	disjoint := expect_error(generic_tree(source, destination))?
	expect_equal(disjoint.kind, "EEXIST")?
	expect_equal((list(destination)?).length(), 1)?
	expect_equal(text("{destination}/keep")?, "keep")?
	copy(
		source,
		destination,
		CopyOptions(
			recursive: true,
			filter: fn(s: String, d: String) Bool: false
		),
	)?
	expect_equal((list(destination)?).length(), 1)?
	copy(source, destination, CopyOptions(recursive: true, replace: true))?
	expect_equal(text("{destination}/new")?, "new")?
	expect_equal(text("{destination}/keep")?, "keep")?

test "filesystem directory creation defaults to requiring an existing parent":
	temporary := temporary("manuscript-default-directory-") | expect_ok?
	create := create_directory
	alias := create_directory
	child := "{temporary.path()}/missing/child"
	(rejected(alias(child))?)
	(rejected(create(child, false))?)
	(rejected(generic_directory(child))?)
	(list(temporary.path()) | expect_ok?).length() | expect_equal(0)?
	(create(child, recursive: true) | expect_ok?)
	((stat(child, follow_links: false) | expect_ok?).is_directory()) | expect_true?
	(generic_directory("{temporary.path()}/generic") | expect_ok?)
	(rejected(create(""))?)

test "filesystem removal defaults to retaining nonempty trees":
	temporary := temporary("manuscript-default-remove-") | expect_ok?
	directory := "{temporary.path()}/nonempty"
	path := "{directory}/keep"
	create_directory(directory) | expect_ok?
	write_file(path, "keep").wait() | expect_ok?

	eraser := remove
	alias := remove
	(rejected(alias(directory))?)
	(rejected(eraser(directory, false))?)
	(rejected(generic_remove(directory))?)
	(text(path)?) | expect_equal("keep")?
	(remove(directory, recursive: true) | expect_ok?)

	empty := "{temporary.path()}/empty"
	create_directory(empty) | expect_ok?
	(alias(empty) | expect_ok?)
	write_file("{temporary.path()}/file", "file").wait() | expect_ok?
	(generic_remove("{temporary.path()}/file") | expect_ok?)
	(rejected(eraser(""))?)

test "filesystem default preparation retains written argument order":
	temporary := temporary("manuscript-default-order-") | expect_ok?
	var log: List[String] = []
	(
		write_file(
			data: data_argument(var log),
			path: argument(var log, "path", "{temporary.path()}/ordered"),
		).wait() | expect_ok?
	)
	log | expect_equal(["data", "path"])?

	copy := copy
	(
		copy(
			destination: argument(
				var log,
				"destination",
				"{temporary.path()}/copy",
			),
			source: argument(
				var log,
				"source",
				"{temporary.path()}/ordered",
			),
		) | expect_ok?
	)
	log | expect_equal(["data", "path", "destination", "source"])?
