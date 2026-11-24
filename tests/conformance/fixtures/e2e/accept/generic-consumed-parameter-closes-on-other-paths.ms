// conform: tags=generics,tier-io
// conform: phase=test
import (
	panic from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker {
	id Int
	log String
}

fn move Marker.close() Void! => append_file(self.log, f"{self.id},").wait()

fn keep_or_drop[T](drop Bool, move value T?) T? {
	if drop { return null }
	return value or panic("called Optional.get() on null")
}

test "a generic parameter a path does not move is closed on that path" {
	tmp := temporary("generic-consumed-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?

	dropped := keep_or_drop(true, Marker(1, log.clone()))
	expect_equal(dropped == null, true)?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "1,")?

	kept := keep_or_drop(false, Marker(2, log.clone()))
	expect_equal(kept == null, false)?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "1,")?
}
