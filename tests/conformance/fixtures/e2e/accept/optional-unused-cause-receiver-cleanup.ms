// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_fault, expect_ok from "@std/test/test.ms",
)

type Marker:
	id: Int
	log: String
	fail: Bool

fn move Marker.close() Void!:
	append_file(self.log, f"{self.id},").wait()?
	if self.fail: return error(Error("cause close failed"))

fn source(move log: String) Marker?: Marker(1, log, false)

fn discard(log: String) Void:
	_kept := source(log.clone()).ok_or(Marker(2, log, true))

test "closing an unused cause does not lose the retained receiver on fault":
	tmp := temporary("cause-fault-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?

	_fault := expect_fault(fn: discard(log.clone()))?
	expect_equal(read_file(log).wait().get().decode_utf8().get_or(""), "2,1,")?

fn normal_transfer(log: String) Void!:
	kept := source(log.clone()).ok_or(Marker(2, log.clone(), false))
	expect_equal(read_file(log).wait().get().decode_utf8().get_or(""), "2,")?
	expect_equal(kept.get().id, 1)?

test "successful cause cleanup transfers the protected receiver exactly once":
	tmp := temporary("cause-transfer-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	normal_transfer(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get_or(""), "2,1,")?

fn failing_callback(move log: String) fn() Marker:
	captured := Marker(2, log, true)
	return fn: Marker(3, captured.log.clone(), false)

fn discard_callback(move log: String) Void:
	_kept := source(log.clone()).ok_or_else(failing_callback(log))

// Capture closer thunks discard returned close errors; this is a cleanup control, not a
// fault.
test "unused owning callback cleanup closes its capture without invoking the callback":
	tmp := temporary("cause-callback-fault-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	discard_callback(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get_or(""), "2,1,")?
