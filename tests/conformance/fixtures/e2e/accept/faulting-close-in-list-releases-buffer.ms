// conform: tags=testing,scope-cleanup,faults
// conform: phase=test
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	expect_true from "@std/test/test.ms",
)

// A close that returns an error while a list holding the resource is closed, at scope
// end, with a fault pending, or inside a closure that captured the list, still releases
// the list
// buffer: each fault runs in a promise and the leak sweep fails the fixture on any block left
// at exit.
type Marker:
	label: String

fn move Marker.close() Void!: error(Error("marker closed"))

fn list_under_fault(move label: String) Void:
	markers := [Marker(label)]
	panic("body fault")
	void markers.length()

fn list_at_scope_end(move label: String) Void:
	markers := [Marker(label.clone()), Marker(label)]
	void markers.length()

fn captured_list(label: String) fn() Int:
	markers := [Marker(label)]
	size := markers.length()
	return fn: markers.length() + size

fn drop_captured_list(label: String) Void:
	action := captured_list(label)
	void action()

fn faults(work: fn() Void) Bool:
	return promise(fn: ok(work()), options: PromiseOptions(placement: Placement.Here)).wait().is_error()

test "a list whose element close faults during a pending fault is released":
	expect_true(faults(fn: list_under_fault("a marker label that needs a heap block")))?

test "a list whose element close faults at scope end is released":
	expect_true(faults(fn: list_at_scope_end("a marker label that needs a heap block")))?

test "a closure capturing a list whose element close faults releases the list":
	expect_true(
		faults(fn: drop_captured_list("a marker label that needs a heap block"))
	)?
