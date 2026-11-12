// conform: tags=testing,scope-cleanup,faults
// conform: phase=test
import (
	local_promise from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	expect_true from "@std/test/test.ms",
	nanoseconds, sleep from "@std/time.ms",
)

// A fault in a close ends the program, or the promise it runs in, but the memory of the
// value being closed still goes back, also when the close suspends first: each fault
// below runs in a promise, and the leak sweep fails the fixture on any block left at
// exit.
type Holder:
	label: String
	breaks: Bool

fn var Holder.close() Unit!:
	_ := sleep(nanoseconds(1000)).wait()
	if self.breaks:
		panic("close fault")

fn hold_then_break(label: String) Unit:
	holder := Holder(label, true)
	_ := holder.breaks

fn hold_fault_and_break(label: String) Unit:
	holder := Holder(label, true)
	panic("body fault")

	_ := holder.breaks

type Door:
	label: String
	fail: Bool

fn var Door.close() Unit!:
	_ := sleep(nanoseconds(1000)).wait()
	if self.fail: panic("capture close panic")

fn captured(label: String) fn() Int:
	door := Door(label, true)
	return fn: door.label.byte_length()

type Envelope:
	label: String
	callback: fn() Int

fn replace_old_capture(label: String) Unit:
	var items = [Envelope(label.clone(), captured(label.clone()))]
	items.set(0, Envelope(label, fn: 4))

fn drop_capture(label: String) Unit:
	action := captured(label)
	_ := action()

fn temporary_list(label: String) Unit:
	_old := [Door(label.clone(), false)].replace(0, Door(label, true))

fn faults(work: fn() Unit) Bool:
	return local_promise(fn: ok(work())).wait().is_error()

test "a fault in close on a normal return releases the value":
	expect_true(faults(fn: hold_then_break("a holder label that needs a heap block")))?

test "a fault in close during a pending fault releases the value":
	expect_true(
		faults(
			fn: hold_fault_and_break(
				"a holder label that needs a heap block"
			)
		)
	)?

test "a captured resource whose close faults releases its parts":
	expect_true(faults(fn: drop_capture("a capture label that needs a heap block")))?

test "replacing a list element whose capture close faults keeps the new owner":
	expect_true(faults(fn: replace_old_capture("a list label that needs a heap block")))?

test "a temporary list whose element close faults releases the list":
	expect_true(faults(fn: temporary_list("a temporary label that needs a heap block")))?
