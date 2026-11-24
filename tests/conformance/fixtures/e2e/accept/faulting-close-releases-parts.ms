// conform: tags=testing,scope-cleanup,faults
// conform: phase=test
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	expect_true from "@std/test/test.ms",
	nanoseconds, sleep from "@std/time.ms",
)

// A fault in a close ends the program, or the promise it runs in, but the memory of the
// value being closed still goes back, also when the close suspends first: each fault
// below runs in a promise, and the leak sweep fails the fixture on any block left at
// exit.
type Holder:
	label String
	breaks Bool

fn move Holder.close() Void!:
	void sleep(nanoseconds(1000)).wait()
	if self.breaks:
		panic("close fault")

fn hold_then_break(move label String) Void:
	holder := Holder(label, true)
	void holder.breaks

fn hold_fault_and_break(move label String) Void:
	holder := Holder(label, true)
	panic("body fault")

	void holder.breaks

type Door:
	label String
	fail Bool

fn move Door.close() Void!:
	void sleep(nanoseconds(1000)).wait()
	if self.fail: panic("capture close panic")

fn captured(move label String) fn() Int:
	door := Door(label, true)
	return () => door.label.length()

type Envelope:
	label String
	callback fn() Int

fn replace_old_capture(move label String) Void:
	var items = [Envelope(label.clone(), captured(label.clone()))]
	items.set(0, Envelope(label, () => 4))

fn drop_capture(move label String) Void:
	action := captured(label)
	void action()

fn temporary_list(move label String) Void:
	_old := [Door(label.clone(), false)].replace(0, Door(label, true))

type Shelf:
	slot Holder?

enum Choice:
	Held(door Holder, note String)
	Empty

fn shelf_close(move label String) Void:
	shelf := Shelf(Holder(label, true))
	void shelf.slot

fn choice_close(label String) Void:
	choice := Choice.Held(Holder(label.clone(), true), f"{label} and a note")
	void choice

fn optional_close_during_fault(move label String) Void:
	var held Holder? = Holder(label, true)
	panic("body fault")

	void held

fn faults(work fn() Void) Bool:
	return promise(() => ok(work()), options: PromiseOptions(placement: Placement.Here)).wait().is_error()

test "a fault in close on a normal return releases the value":
	expect_true(faults(() => hold_then_break("a holder label that needs a heap block")))?

test "a fault in close during a pending fault releases the value":
	expect_true(
		faults(
			() => hold_fault_and_break(
				"a holder label that needs a heap block"
			)
		)
	)?

test "a captured resource whose close faults releases its parts":
	expect_true(faults(() => drop_capture("a capture label that needs a heap block")))?

test "replacing a list element whose capture close faults keeps the new owner":
	expect_true(faults(() => replace_old_capture("a list label that needs a heap block")))?

test "a temporary list whose element close faults releases the list":
	expect_true(faults(() => temporary_list("a temporary label that needs a heap block")))?

test "a faulting close of an optional payload releases it":
	expect_true(faults(() => shelf_close("a shelf label that needs a heap block")))?

test "a faulting close of an alternative case releases its other fields":
	expect_true(faults(() => choice_close("a choice label that needs a heap block")))?

test "a faulting optional close during a pending fault releases the payload":
	expect_true(
		faults(
			() => optional_close_during_fault(
				"an optional label that needs a heap block"
			)
		)
	)?

fn remove_out_of_range(move label String) Void:
	var items = [Envelope(label, () => 1)]
	items.remove(5)

test "an index fault of an in-place list edit releases the list":
	expect_true(faults(() => remove_out_of_range("a remove label that needs a heap block")))?

fn set_out_of_range(move label String) Void:
	var items = [Envelope(label.clone(), () => 1)]
	items.set(5, Envelope(label, () => 2))

test "an index fault of set releases the incoming element":
	expect_true(faults(() => set_out_of_range("a set label that needs a heap block")))?

fn insert_out_of_range(move label String) Void:
	var items = [Envelope(label.clone(), () => 1)]
	items.insert(5, Envelope(label, () => 2))

test "an index fault of insert releases the incoming element":
	expect_true(faults(() => insert_out_of_range("an insert label that needs a heap block")))?

fn replace_out_of_range(move label String) Void:
	var items = [label.clone()]
	void items.replace(5, label)

test "an index fault of replace releases the incoming element":
	expect_true(faults(() => replace_out_of_range("a replace label that needs a heap block")))?

fn splice_out_of_range(move label String) Void:
	var items = [label.clone()]
	items.splice(5, 0, [label])

test "a range fault of splice releases the replacement":
	expect_true(faults(() => splice_out_of_range("a splice label that needs a heap block")))?

fn fill_out_of_range(move label String) Void:
	var items = [label.clone()]
	items.fill(label, 0, 9)

test "a range fault of fill releases the value":
	expect_true(faults(() => fill_out_of_range("a fill label that needs a heap block")))?

fn fill_empty_range(move label String) Void:
	var items = [label.clone()]
	items.fill(label, 0, 0)

test "fill over an empty range releases the value":
	expect_true(not faults(() => fill_empty_range("a fill label that needs a heap block")))?
