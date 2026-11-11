import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_fault, expect_some from "@std/test/test.ms",
)

type Resource:
	id: Int
	path: String

impl Closeable for Resource:
	var fn close() Unit!:
		append_file(self.path, "{self.id},").wait()?

interface Observer:
	fn observe(value: Resource?) Bool

type Reader:
	tag: Int

impl Observer for Reader:
	fn observe(value: Resource?) Bool: value.is_some()

fn log_text(path: String) String!:
	bytes := read_file(path).wait()?
	return ok(expect_some(bytes.decode_utf8())?)

test "interface reader closes intact temporary wrapper":
	directory := temporary("iface-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	reader: Observer := Reader(1)
	expect_equal(reader.observe(Resource(1, path.clone())), true)?
	expect_equal(log_text(path)?, "1,")?
