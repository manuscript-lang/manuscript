// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	compile from "@std/string.ms",
	expect_contains, expect_equal from "@std/test/test.ms",
)

test "regex hexadecimal escapes reject signed numbers":
	for pattern in ["\\x+1", "\\x\{+41\}", "[\\x+1]", "[\\x\{+41\}]"]:
		cause := compile(pattern).err()
		expect_equal(cause.kind, "EBADMSG")?
		expect_contains(cause.message, "regular expression: invalid data: ")?

test "regex hexadecimal escapes accept only digit sequences":
	for pattern in ["\\x41", "\\x\{41\}", "[\\x41]", "[\\x\{41\}]"]:
		regex := compile(pattern)?
		expect_equal(regex.matches("A"), true)?
		expect_equal(regex.matches("B"), false)?
