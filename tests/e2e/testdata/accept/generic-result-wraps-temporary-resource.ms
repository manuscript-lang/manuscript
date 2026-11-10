import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_some from "@std/test/test.ms",
)

type Resource:
	id: Int
	path: String

impl Closeable for Resource:
	var fn close() Unit!:
		try append_file(self.path, "{self.id},").wait()

fn wrapped[T](value: T) Result[T, String]:
	return ok(value)

fn rejected[T](value: T) Result[Int, T]:
	return error(value)

fn log_text(path: String) String!:
	bytes := try read_file(path).wait()
	return ok(try expect_some(bytes.decode_utf8()))

fn use_temporary(path: String) Unit!:
	result := wrapped(Resource(1, path.clone()))
	try expect_equal(result.is_ok(), true)
	try expect_equal(try log_text(path), "")

fn use_error_case(path: String) Unit!:
	result := rejected(Resource(2, path.clone()))
	try expect_equal(result.is_error(), true)
	try expect_equal(try log_text(path), "")

fn use_named(path: String) Unit!:
	named := Resource(3, path.clone())
	result := wrapped(named)
	try expect_equal(result.is_ok(), true)
	try expect_equal(try log_text(path), "")

test "a Result built around a temporary resource owns it and closes it once":
	directory := try temporary("wrapped-ok-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()
	try use_temporary(path.clone())
	try expect_equal(try log_text(path), "1,")

test "an error case around a temporary resource closes it once":
	directory := try temporary("wrapped-error-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()
	try use_error_case(path.clone())
	try expect_equal(try log_text(path), "2,")

test "a named resource wrapped by the helper is closed only by its owner":
	directory := try temporary("wrapped-named-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()
	try use_named(path.clone())
	try expect_equal(try log_text(path), "3,")
