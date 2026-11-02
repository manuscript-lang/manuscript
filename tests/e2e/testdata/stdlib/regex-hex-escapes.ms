import expect_equal from "@std/test/test.ms"
import compile from "@std/string.ms"

test "regex hexadecimal escapes reject signed numbers":
    for pattern in ["\\x+1", "\\x\{+41\}", "[\\x+1]", "[\\x\{+41\}]"]:
        try expect_equal(
            compile(pattern).err(),
            Error(
                "regular expression: invalid data", kind: ErrorCategory.InvalidData
            )
        )

test "regex hexadecimal escapes accept only digit sequences":
    for pattern in ["\\x41", "\\x\{41\}", "[\\x41]", "[\\x\{41\}]"]:
        let regex = try compile(pattern)
        try expect_equal(regex.matches("A"), true)
        try expect_equal(regex.matches("B"), false)
