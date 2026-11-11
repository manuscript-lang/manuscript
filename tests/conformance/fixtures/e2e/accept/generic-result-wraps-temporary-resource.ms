// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_some from "@std/test/test.ms",
)

type Resource:
	id: Int
	path: String

fn var Resource.close() Unit!:
	append_file(self.path, "{self.id},").wait()?

fn wrapped[T](value: T) Result[T, String]:
	return ok(value)

fn rejected[T](value: T) Result[Int, T]:
	return error(value)

fn log_text(path: String) String!:
	bytes := read_file(path).wait()?
	return ok(expect_some(bytes.decode_utf8())?)

fn use_temporary(path: String) Unit!:
	result := wrapped(Resource(1, path.clone()))
	expect_equal(result.is_ok(), true)?
	expect_equal(log_text(path)?, "")?

fn use_error_case(path: String) Unit!:
	result := rejected(Resource(2, path.clone()))
	expect_equal(result.is_error(), true)?
	expect_equal(log_text(path)?, "")?

fn use_named(path: String) Unit!:
	named := Resource(3, path.clone())
	result := wrapped(named)
	expect_equal(result.is_ok(), true)?
	expect_equal(log_text(path)?, "")?

test "a Result built around a temporary resource owns it and closes it once":
	directory := temporary("wrapped-ok-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	use_temporary(path.clone())?
	expect_equal(log_text(path)?, "1,")?

test "an error case around a temporary resource closes it once":
	directory := temporary("wrapped-error-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	use_error_case(path.clone())?
	expect_equal(log_text(path)?, "2,")?

test "a named resource wrapped by the helper is closed only by its owner":
	directory := temporary("wrapped-named-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	use_named(path.clone())?
	expect_equal(log_text(path)?, "3,")?
