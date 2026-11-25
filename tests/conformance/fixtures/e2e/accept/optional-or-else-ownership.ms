// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

fn text(value Int) String? => f"dynamic optional payload {value}"

fn texts(value Int) List[String]? => [f"dynamic optional payload {value}"]

fn unexpected_text() String? => panic("present Optional must not call fallback")

fn unexpected_texts() List[String]? => panic("present Optional must not call fallback")

type Fallback {
	calls Int
}

fn var Fallback.create() String? {
	self.calls += 1
	return f"fallback {self.calls}"
}

test "or_else transfers an owned String Optional call" {
	kept := text(1) or unexpected_text()
	expect_equal(
		kept or panic("called Optional.get() on null"),
		"dynamic optional payload 1",
	)?
}

test "or_else transfers a last-use String Optional" {
	present := text(2)
	kept := present or unexpected_text()
	expect_equal(
		kept or panic("called Optional.get() on null"),
		"dynamic optional payload 2",
	)?
}

test "or_else takes its receiver, so a caller that keeps a String Optional clones it" {
	present := text(3)
	kept := present.clone() or unexpected_text()
	expect_equal(
		present or panic("called Optional.get() on null"),
		"dynamic optional payload 3",
	)?
	expect_equal(
		kept or panic("called Optional.get() on null"),
		"dynamic optional payload 3",
	)?
}

test "or_else transfers an owned List Optional" {
	kept := texts(4) or unexpected_texts()
	expect_equal(
		kept or panic("called Optional.get() on null"),
		["dynamic optional payload 4"],
	)?
}

test "or_else takes its receiver, so a caller that keeps a List Optional clones it" {
	present := texts(5)
	kept := present.clone() or unexpected_texts()
	expect_equal(
		present or panic("called Optional.get() on null"),
		["dynamic optional payload 5"],
	)?
	expect_equal(
		kept or panic("called Optional.get() on null"),
		["dynamic optional payload 5"],
	)?
}

test "or_else invokes a missing fallback once and skips a present fallback" {
	var fallback = Fallback(0)
	missing String? := null
	recovered := missing or fallback.create()
	expect_equal(recovered or panic("called Optional.get() on null"), "fallback 1")?

	kept := text(6) or fallback.create()
	expect_equal(
		kept or panic("called Optional.get() on null"),
		"dynamic optional payload 6",
	)?
	expect_equal(fallback.calls, 1)?
}

test "or_else permits a fallback that stays absent" {
	missing String? := null
	kept := missing or null
	expect_equal(kept, null)?
}

test "a closure over or_else copies its captured Optional for each call" {
	held := text(7)
	bound := fn(fallback fn() String?) String? => held.clone() or fallback()
	first := bound(unexpected_text)
	second := bound(unexpected_text)
	expect_equal(
		first or panic("called Optional.get() on null"),
		"dynamic optional payload 7",
	)?
	expect_equal(
		second or panic("called Optional.get() on null"),
		"dynamic optional payload 7",
	)?
}

fn text_callback(fail Bool) (fn() String?)! {
	if fail { return error(Error("callback unavailable")) }
	return ok(unexpected_text)
}

test "owned data receiver keeps its value across a later try" {
	kept := text(8) or (text_callback(false)?)()
	expect_equal(
		kept or panic("called Optional.get() on null"),
		"dynamic optional payload 8",
	)?

	original := text(9)
	moved := original or (text_callback(false)?)()
	expect_equal(
		moved or panic("called Optional.get() on null"),
		"dynamic optional payload 9",
	)?
}

test "a cloned data receiver stays with its caller across a later try" {
	original := text(10)
	kept := original.clone() or (text_callback(false)?)()
	expect_equal(
		original or panic("called Optional.get() on null"),
		"dynamic optional payload 10",
	)?
	expect_equal(
		kept or panic("called Optional.get() on null"),
		"dynamic optional payload 10",
	)?
}
