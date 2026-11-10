import (
	expect_contains, expect_equal from "@std/test/test.ms",
	compile from "@std/string.ms",
)

test "regex hexadecimal escapes reject signed numbers":
	for pattern in ["\\x+1", "\\x\{+41\}", "[\\x+1]", "[\\x\{+41\}]"]:
		cause := compile(pattern).err()
		try expect_equal(cause.kind, "EBADMSG")
		try expect_contains(cause.message, "regular expression: invalid data: ")

test "regex hexadecimal escapes accept only digit sequences":
	for pattern in ["\\x41", "\\x\{41\}", "[\\x41]", "[\\x\{41\}]"]:
		regex := try compile(pattern)
		try expect_equal(regex.matches("A"), true)
		try expect_equal(regex.matches("B"), false)
