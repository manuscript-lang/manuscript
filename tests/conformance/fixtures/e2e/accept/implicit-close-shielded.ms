// conform: tags=testing,tier-io
// conform: phase=test
import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	Closeable, panic from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal,
	expect_error,
	expect_fault,
	expect_ok,
	expect_true from "@std/test/test.ms",
	nanoseconds, sleep from "@std/time.ms",
)

// The scope-end close of a binding runs on every exit and is shielded like any other
// close: cancellation and a pending fault do not interrupt it, and a fault inside it
// follows the cleanup-failure table.
type Holder:
	dir: String
	id: Int
	pause: Bool
	breaks: Bool

// Close records itself by writing a marker file named after the holder.
fn move Holder.close() Void!:
	if self.pause:
		void sleep(nanoseconds(5000000)).wait()
	void write_file(f"{self.dir}/{self.id}", "closed", true).wait()
	if self.breaks:
		panic("close fault")

fn closed(dir: String, name: String) Bool:
	return read_file(f"{dir}/{name}").wait().is_ok()

fn hold_and_wait(move dir: String,id: Int,pause: Bool) Int:
	holder := Holder(dir, id, pause, false)
	void sleep(nanoseconds(5000000000)).wait()
	return holder.id

fn hold_and_fault(move dir: String, id: Int) Void:
	holder := Holder(dir, id, false, false)
	panic("body fault")
	void holder.id

fn hold_then_break(move dir: String, id: Int) Void:
	holder := Holder(dir, id, false, true)
	void holder.id

fn hold_fault_and_break(move dir: String,id: Int) Void:
	holder := Holder(dir, id, false, true)
	panic("body fault")
	void holder.id

fn cancel_a_holder(dir: String, id: Int, pause: Bool) Void:
	work := promise(fn: ok(hold_and_wait(dir.clone(), id, pause)))
	_ignored := work.with(
		options: PromiseOptions(timeout: nanoseconds(20000000))
	).wait()

// A statement that discards a popped resource closes it in place, shielded too. The
// marker `started` says the body is running, so the cancel below lands during the close
// and not before the body began.
fn pop_and_discard(move dir: String,id: Int) Int:
	void write_file(f"{dir}/started", "started", true).wait()

	var held = [Holder(dir, id, true, false)]
	held.pop()
	void sleep(nanoseconds(5000000000)).wait()
	return held.length()

fn cancel_a_discard(dir: String, id: Int) Void:
	stop := cancel_switch()
	work := promise(fn: ok(pop_and_discard(dir.clone(), id))).with(
		options: PromiseOptions(cancel: stop.signal())
	)
	var waited = 0

	while not closed(dir, "started") and waited < 5000:
		void sleep(nanoseconds(1000000)).wait()
		waited += 1

	stop.cancel()
	void work.wait()

fn faulting_holder(move dir: String, id: Int) Void!:
	hold_and_fault(dir, id)

test "cancellation closes the binding":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	cancel_a_holder(dir.clone(), 1, false)
	expect_true(closed(dir, "1"))?

test "cancellation does not interrupt a close that suspends":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	cancel_a_holder(dir.clone(), 2, true)
	expect_true(closed(dir, "2"))?

test "a fault unwinding the scope closes the binding":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	message := expect_fault(fn: hold_and_fault(dir.clone(), 3))?
	expect_equal(message, "body fault")?
	expect_true(closed(dir, "3"))?

test "a faulted promise closes its binding before wait reports":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	work := promise(fn: faulting_holder(dir.clone(), 4))
	_reason := work.wait() | expect_error?
	expect_true(closed(dir, "4"))?

test "a fault in close on a normal return is the fault":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	message := expect_fault(fn: hold_then_break(dir.clone(), 5))?
	expect_equal(message, "close fault")?
	expect_true(closed(dir, "5"))?

test "a fault in close does not replace a pending fault":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	message := expect_fault(fn: hold_fault_and_break(dir.clone(), 6))?
	expect_equal(message, "body fault")?
	expect_true(closed(dir, "6"))?

test "cancellation does not interrupt the close of a discarded result":
	temporary := temporary("manuscript-shield-") | expect_ok?
	dir := temporary.path()
	cancel_a_discard(dir.clone(), 7)
	expect_true(closed(dir, "7"))?
