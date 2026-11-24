// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
	id Int
	log String
	closed Bool = false

fn move Marker.close() Void!:
	if not self.closed:
		self.closed = true
		append_file(self.log, f"{self.id},").wait()?

fn result(id Int, log String) Marker!Error: ok(Marker(id, log.clone()))

fn optional(id Int, log String) Marker?: Marker(id, log.clone())

fn transfer_result_local(log String) Void:
	original := result(1, log)
	_kept := original.or_else(fn cause: error(cause))

fn transfer_result_temporary(log String) Void:
	_kept := result(2, log).or_else(fn cause: error(cause))

fn transfer_optional_local(log String) Void:
	original := optional(3, log)
	_kept := original or null

fn transfer_optional_temporary(log String) Void:
	_kept := optional(4, log) or null

test "native wrapper passthrough transfers resources without duplicating owners":
	tmp := temporary("wrapper-passthrough-") | expect_ok?
	log := f"{tmp.path()}/log"
	transfer_result_local(log.clone())
	transfer_result_temporary(log.clone())
	transfer_optional_local(log.clone())
	transfer_optional_temporary(log.clone())

	events := read_file(log).wait().get().decode_utf8() or ""
	expect_equal(events, "1,2,3,4,")?

// `or_else` takes the Result; its callback reads the error, which closes after the call.
fn recover_resource_error(log String) Void!:
	original Int!Marker := error(Marker(5, log.clone()))
	recovered := original.or_else(fn cause: ok(cause.id))
	expect_equal(recovered.get(), 5)?

test "or_else takes a Result holding a resource error and closes it once":
	tmp := temporary("wrapper-error-borrow-") | expect_ok?
	log := f"{tmp.path()}/log"
	recover_resource_error(log.clone())?

	events := read_file(log).wait().get().decode_utf8() or ""
	expect_equal(events, "5,")?

fn optional_callback(fail Bool) (fn() Marker?)!:
	if fail: return error(Error("callback unavailable"))
	return ok(fn: null)

fn result_callback(fail Bool) (fn(Error) Marker!Error)!:
	if fail: return error(Error("callback unavailable"))
	return ok(fn cause: error(cause))

fn held_result_temporary(id Int, log String, fail Bool) Void!:
	_kept := result(id, log).or_else(result_callback(fail)?)

fn held_result_local(id Int, log String, fail Bool) Void!:
	original := result(id, log)
	_kept := original.or_else(result_callback(fail)?)

fn held_optional_temporary(id Int, log String, fail Bool) Void!:
	_kept := optional(id, log) or (optional_callback(fail)?)()

fn held_optional_local(id Int, log String, fail Bool) Void!:
	original := optional(id, log)
	_kept := original or (optional_callback(fail)?)()

test "owned native receivers stay closeable until later try arguments succeed":
	tmp := temporary("wrapper-held-receiver-") | expect_ok?
	log := f"{tmp.path()}/log"
	held_result_temporary(1, log.clone(), false)?
	held_result_local(2, log.clone(), false)?
	held_optional_temporary(3, log.clone(), false)?
	held_optional_local(4, log.clone(), false)?
	expect_equal(held_result_temporary(5, log.clone(), true).is_error(), true)?
	expect_equal(held_result_local(6, log.clone(), true).is_error(), true)?
	// `or` runs its right side only for an absent left, so a present receiver never reaches the failing callback.
	expect_equal(held_optional_temporary(7, log.clone(), true).is_error(), false)?
	expect_equal(held_optional_local(8, log.clone(), true).is_error(), false)?

	events := read_file(log).wait().get().decode_utf8() or ""
	expect_equal(events, "1,2,3,4,5,6,7,8,")?

fn borrowed_error_callback(fail Bool) (fn(Marker) Int!Marker)!:
	if fail: return error(Error("callback unavailable"))
	return ok(fn cause: ok(cause.id))

fn borrowed_error_before_try(id Int, log String, fail Bool) Void!:
	original Int!Marker := error(Marker(id, log.clone()))
	recovered := original.or_else(borrowed_error_callback(fail)?)
	expect_equal(recovered.get(), id)?

test "or_else takes its receiver before a later try fails":
	tmp := temporary("wrapper-borrowed-receiver-") | expect_ok?
	log := f"{tmp.path()}/log"
	borrowed_error_before_try(9, log.clone(), false)?
	expect_equal(borrowed_error_before_try(10, log.clone(), true).is_error(), true)?

	events := read_file(log).wait().get().decode_utf8() or ""
	expect_equal(events, "9,10,")?
