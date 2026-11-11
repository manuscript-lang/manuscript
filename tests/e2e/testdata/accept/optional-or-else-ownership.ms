import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

fn text(value: Int) String?: "dynamic optional payload {value}"

fn texts(value: Int) List[String]?: ["dynamic optional payload {value}"]

fn unexpected_text() String?: panic("present Optional must not call fallback")

fn unexpected_texts() List[String]?: panic("present Optional must not call fallback")

type Fallback:
	calls: Int

fn var Fallback.create() String?:
	self.calls += 1
	return "fallback {self.calls}"

test "or_else transfers an owned String Optional call":
	kept := text(1).or_else(unexpected_text)
	expect_equal(kept.get(), "dynamic optional payload 1")?

test "or_else transfers a last-use String Optional":
	present := text(2)
	kept := present.or_else(unexpected_text)
	expect_equal(kept.get(), "dynamic optional payload 2")?

test "or_else copies a borrowed String Optional at its declared boundary":
	present := text(3)
	kept := present.or_else(unexpected_text)
	expect_equal(present.get(), "dynamic optional payload 3")?
	expect_equal(kept.get(), "dynamic optional payload 3")?

test "or_else transfers an owned List Optional":
	kept := texts(4).or_else(unexpected_texts)
	expect_equal(kept.get(), ["dynamic optional payload 4"])?

test "or_else copies a borrowed List Optional at its declared boundary":
	present := texts(5)
	kept := present.or_else(unexpected_texts)
	expect_equal(present.get(), ["dynamic optional payload 5"])?
	expect_equal(kept.get(), ["dynamic optional payload 5"])?

test "or_else invokes a missing fallback once and skips a present fallback":
	var fallback = Fallback(0)
	missing: String? := none
	recovered := missing.or_else(fn: fallback.create())
	expect_equal(recovered.get(), "fallback 1")?

	kept := text(6).or_else(fn: fallback.create())
	expect_equal(kept.get(), "dynamic optional payload 6")?
	expect_equal(fallback.calls, 1)?

test "or_else permits a fallback that stays absent":
	missing: String? := none
	kept := missing.or_else(fn: none)
	expect_equal(kept, none)?

test "bound or_else preserves its captured Optional across calls":
	bound := text(7).or_else
	first := bound(unexpected_text)
	second := bound(unexpected_text)
	expect_equal(first.get(), "dynamic optional payload 7")?
	expect_equal(second.get(), "dynamic optional payload 7")?

fn text_callback(fail: Bool) (fn() String?)!:
	if fail: return error(Error("callback unavailable"))
	return ok(unexpected_text)

test "owned data receiver keeps its value across a later try":
	kept := text(8).or_else(text_callback(false)?)
	expect_equal(kept.get(), "dynamic optional payload 8")?

	original := text(9)
	moved := original.or_else(text_callback(false)?)
	expect_equal(moved.get(), "dynamic optional payload 9")?

test "borrowed data receiver remains borrowed across a later try":
	original := text(10)
	kept := original.or_else(text_callback(false)?)
	expect_equal(original.get(), "dynamic optional payload 10")?
	expect_equal(kept.get(), "dynamic optional payload 10")?
