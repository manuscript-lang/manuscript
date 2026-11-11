import (
	expect_equal, expect_fault, expect_some from "@std/test/test.ms",
	TextCursor, cursor from "@std/text.ms",
)

fn read_all(text: String) List[String]:
	var at = cursor(text)
	var out: List[String] = []
	while not at.is_done():
		out.append(at.read().get())
	return out

test "a cursor reads every scalar width in order and matches chars":
	for text in ["", "abc", "héllo wörld", "日本語", "a🙂b🙂", "e\u{301}x"]:
		expect_equal(read_all(text), text.chars())?

test "peek does not move and the end reads none":
	var at = cursor("é!")
	expect_equal(at.peek(), "é")?
	expect_equal(at.peek(), "é")?
	expect_equal(at.offset(), 0)?
	expect_equal(at.read(), "é")?
	expect_equal(at.offset(), 2)?
	expect_equal(at.read(), "!")?
	expect_equal(at.is_done(), true)?
	expect_equal(at.peek(), none)?
	expect_equal(at.read(), none)?

test "marks slice and rewind on scalar boundaries":
	var at = cursor("héllo wörld")
	start := at.offset()
	while not at.is_done():
		if at.read().get() == " ": break
	expect_equal(at.since(start), "héllo ")?

	word := at.offset()
	at.read()
	at.read()
	expect_equal(at.since(word), "wö")?
	at.seek(start)
	expect_equal(at.read(), "h")?
	expect_equal(at.since(start), "h")?

fn check_since(at: TextCursor) Unit:
	_text := at.since(1)

test "a mark inside a scalar or past the end faults":
	var at = cursor("é")
	_a := expect_fault(fn: at.seek(1))?
	_b := expect_fault(fn: at.seek(3))?
	_c := expect_fault(fn: check_since(at))?

test "a long non-ASCII scan is linear":
	text := "héllo wörld ünï ".repeat(6250).get("")
	var at = cursor(text)
	var found = 0
	while not at.is_done():
		if at.read().get() == "ö": found += 1
	expect_equal(found, 6250)?
