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

fn accepted() Int!: ok(1)

fn failing() Int!: error(Error("stop"))

fn observed(value: Resource?, tail: Int = accepted()?) Bool!:
	return ok(value.is_some() or tail > 0)

fn refused(value: Resource?, tail: Int = failing()?) Bool!:
	return ok(value.is_some() or tail > 0)

fn log_text(path: String) String!:
	bytes := read_file(path).wait()?
	return ok(expect_some(bytes.decode_utf8())?)

test "a temporary passed to a call with a fallible default closes once":
	directory := temporary("fallible-default-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(observed(Resource(3, path.clone()))?, true)?
	expect_equal(log_text(path)?, "3,")?

test "a temporary closes when the fallible default fails":
	directory := temporary("fallible-default-fails-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(refused(Resource(4, path.clone())).is_error(), true)?
	expect_equal(log_text(path)?, "4,")?

test "a named resource lent to a call with a fallible default is not closed early":
	directory := temporary("fallible-default-named-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	named := Resource(5, path.clone())
	expect_equal(observed(named)?, true)?
	expect_equal(log_text(path)?, "")?
	expect_equal(named.id, 5)?
