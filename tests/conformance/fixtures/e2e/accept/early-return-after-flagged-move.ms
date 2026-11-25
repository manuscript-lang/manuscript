// conform: tags=ownership,control-flow,scope-cleanup,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Box {
	text String
	note String?
}

// `value` moves into a field on the early-return path and on one branch of the code after it,
// so it carries a drop flag. The early return must not release it again: the flag is false there.
fn store(var box Box, key String) Void {
	value := key + " and some more text to be long enough"

	if key == "text" {
		box.text = value
		return
	}

	if key == "none" {
		box.note = null
	} else {
		box.note = value
	}
}

test "an early return after a flagged move keeps the moved value" {
	var box = Box(text: "start", note: "first")
	store(box, "text")
	expect_equal(box.text, "text and some more text to be long enough")?
	expect_equal(box.note, "first")?
}

test "the later branches of the same function still store the value" {
	var box = Box(text: "start", note: "first")
	store(box, "other")
	expect_equal(box.note, "other and some more text to be long enough")?
	store(box, "none")
	expect_equal(box.note, null)?
}
