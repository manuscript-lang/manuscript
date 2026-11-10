import (
	Closeable, panic from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	promise, PromiseOptions from "@std/concurrency/promise.ms",
	expect_equal,
	expect_error,
	expect_fault,
	expect_ok,
	expect_true from "@std/test/test.ms",
	nanoseconds, sleep from "@std/time.ms",
)

// The scope-end close of a binding runs on every exit and is shielded like any other close: cancellation and a
// pending fault do not interrupt it, and a fault inside it follows the cleanup-failure table.
type Holder:
	dir: String
	id: Int
	pause: Bool
	breaks: Bool

// Close records itself by writing a marker file named after the holder.
impl Closeable for Holder:
	var fn close() Unit!:
		if self.pause:
			_ := sleep(nanoseconds(5000000)).wait()

		_ := write_file("{self.dir}/{self.id}", "closed", true).wait()
		if self.breaks:
			panic("close fault")

fn closed(dir: String, id: Int) Bool:
	return read_file("{dir}/{id}").wait().is_ok()

fn hold_and_wait(dir: String, id: Int, pause: Bool) Int:
	holder := Holder(dir, id, pause, false)
	_ := sleep(nanoseconds(5000000000)).wait()
	return holder.id

fn hold_and_fault(dir: String, id: Int) Unit:
	holder := Holder(dir, id, false, false)
	panic("body fault")

	_ := holder.id

fn hold_then_break(dir: String, id: Int) Unit:
	holder := Holder(dir, id, false, true)
	_ := holder.id

fn hold_fault_and_break(dir: String, id: Int) Unit:
	holder := Holder(dir, id, false, true)
	panic("body fault")

	_ := holder.id

fn cancel_a_holder(dir: String, id: Int, pause: Bool) Unit:
	work := promise(fn: ok(hold_and_wait(dir.clone(), id, pause)))
	_ignored := work.with(
		options: PromiseOptions(timeout: nanoseconds(20000000))
	).wait()

fn faulting_holder(dir: String, id: Int) Unit!:
	hold_and_fault(dir, id)

test "cancellation closes the binding":
	temporary := temporary("manuscript-shield-") | try expect_ok
	dir := temporary.path()
	cancel_a_holder(dir.clone(), 1, false)
	try expect_true(closed(dir, 1))

test "cancellation does not interrupt a close that suspends":
	temporary := temporary("manuscript-shield-") | try expect_ok
	dir := temporary.path()
	cancel_a_holder(dir.clone(), 2, true)
	try expect_true(closed(dir, 2))

test "a fault unwinding the scope closes the binding":
	temporary := temporary("manuscript-shield-") | try expect_ok
	dir := temporary.path()
	message := try expect_fault(fn: hold_and_fault(dir.clone(), 3))
	try expect_equal(message, "body fault")
	try expect_true(closed(dir, 3))

test "a faulted promise closes its binding before wait reports":
	temporary := temporary("manuscript-shield-") | try expect_ok
	dir := temporary.path()
	work := promise(fn: faulting_holder(dir.clone(), 4))
	_reason := work.wait() | try expect_error
	try expect_true(closed(dir, 4))

test "a fault in close on a normal return is the fault":
	temporary := temporary("manuscript-shield-") | try expect_ok
	dir := temporary.path()
	message := try expect_fault(fn: hold_then_break(dir.clone(), 5))
	try expect_equal(message, "close fault")
	try expect_true(closed(dir, 5))

test "a fault in close does not replace a pending fault":
	temporary := temporary("manuscript-shield-") | try expect_ok
	dir := temporary.path()
	message := try expect_fault(fn: hold_fault_and_break(dir.clone(), 6))
	try expect_equal(message, "body fault")
	try expect_true(closed(dir, 6))
