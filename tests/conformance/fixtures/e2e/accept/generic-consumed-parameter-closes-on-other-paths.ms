// conform: tags=generics,tier-io
// conform: phase=test
import (
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
	id: Int
	log: String

fn var Marker.close() Void!: append_file(self.log, f"{self.id},").wait()

fn keep_or_drop[T](value: T?, drop: Bool) T?:
	if drop: return none
	return value.get()

test "a generic parameter a path does not move is closed on that path":
	tmp := temporary("generic-consumed-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?

	dropped := keep_or_drop(Marker(1, log.clone()), true)
	expect_equal(dropped.is_none(), true)?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
	kept := keep_or_drop(Marker(2, log.clone()), false)
	expect_equal(kept.is_none(), false)?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
