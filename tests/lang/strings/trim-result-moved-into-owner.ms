// conform: tags=strings,ownership
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn long_text() String {
	return "  a heap string that is longer than any inline text, padded  ".upper()
}

// `trim` answers a view of its receiver; a new owner copies it, so the old owner can end first.
test "a trimmed view assigned back to its own variable is a copy" {
	var text = long_text()
	text = text.trim()
	expect_equal(text, "A HEAP STRING THAT IS LONGER THAN ANY INLINE TEXT, PADDED")?
}

test "a trimmed view assigned to another variable survives the source" {
	var kept = ""
	var source = long_text()
	kept = source.trim()
	source = "other"
	expect_equal(kept, "A HEAP STRING THAT IS LONGER THAN ANY INLINE TEXT, PADDED")?
	expect_equal(source, "other")?
}

type Label {
	name String
}

test "a trimmed view assigned to a field of the same record is a copy" {
	var label = Label(long_text())
	label.name = label.name.trim()
	expect_equal(
		label.name,
		"A HEAP STRING THAT IS LONGER THAN ANY INLINE TEXT, PADDED",
	)?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
