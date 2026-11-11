// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
	id: Int
	log: String

fn var Marker.close() Unit!: append_file(self.log, "{self.id},").wait()

fn present() Int?: 7

fn absent() Int?: none

fn marker(id: Int, log: String) Marker: Marker(id, log)

fn optional_marker(id: Int, log: String) Marker?: Marker(id, log)

fn owned(log: String) Unit!:
	kept := present().ok_or(marker(1, log.clone()))
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
	expect_equal(kept.get(), 7)?

fn borrowed_scalar(cause: Int) Unit!:
	kept := present().ok_or(cause)
	expect_equal(kept.get(), 7)?
	expect_equal(cause, 8)?

fn transferred(log: String) Unit!:
	kept := absent().ok_or(marker(3, log.clone()))
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
	expect_equal(kept.is_error(), true)?

fn lazy(log: String) Unit!:
	kept := present().ok_or_else(fn: marker(4, log.clone()))
	expect_equal(kept.get(), 7)?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,")?

fn explicit_wrapped(log: String) Unit!:
	kept := present().ok_or[Marker](optional_marker(5, log.clone()))
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,")?
	expect_equal(kept.get(), 7)?

fn explicit_wrapped_transfer(log: String) Unit!:
	kept := absent().ok_or[Marker](optional_marker(6, log.clone()))
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,")?
	expect_equal(kept.is_error(), true)?

test "unused eager resource causes close immediately only when owned":
	tmp := temporary("unused-cause-") | expect_ok?
	log := "{tmp.path()}/log"
	write_file(log, "").wait()?
	owned(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
	borrowed_scalar(8)?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
	transferred(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,")?
	lazy(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,")?
	explicit_wrapped(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,")?
	explicit_wrapped_transfer(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,3,5,6,")?
