import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
	id: Int
	log: String

impl Closeable for Marker:
	var fn close() Unit!: append_file(self.log, "{self.id},").wait()

fn present() Int?: 7

fn absent() Int?: none

fn marker(id: Int, log: String) Marker: Marker(id, log)

fn optional_marker(id: Int, log: String) Marker?: Marker(id, log)

fn owned(log: String) Unit!:
	kept := present().ok_or(marker(1, log.clone()))
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")
	try expect_equal(kept.get(), 7)

fn borrowed_scalar(cause: Int) Unit!:
	kept := present().ok_or(cause)
	try expect_equal(kept.get(), 7)
	try expect_equal(cause, 8)

fn transferred(log: String) Unit!:
	kept := absent().ok_or(marker(3, log.clone()))
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")
	try expect_equal(kept.is_error(), true)

fn lazy(log: String) Unit!:
	kept := present().ok_or_else(fn: marker(4, log.clone()))
	try expect_equal(kept.get(), 7)
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,")

fn explicit_wrapped(log: String) Unit!:
	kept := present().ok_or[Marker](optional_marker(5, log.clone()))
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,")
	try expect_equal(kept.get(), 7)

fn explicit_wrapped_transfer(log: String) Unit!:
	kept := absent().ok_or[Marker](optional_marker(6, log.clone()))
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,")
	try expect_equal(kept.is_error(), true)

test "unused eager resource causes close immediately only when owned":
	tmp := temporary("unused-cause-") | try expect_ok
	log := "{tmp.path()}/log"
	try write_file(log, "").wait()
	try owned(log.clone())
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")
	try borrowed_scalar(8)
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")
	try transferred(log.clone())
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,")
	try lazy(log.clone())
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,")
	try explicit_wrapped(log.clone())
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,")
	try explicit_wrapped_transfer(log.clone())
	try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,6,")
