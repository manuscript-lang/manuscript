import arguments from "@std/process.ms"
import expect_equal from "@std/test.ms"

test "arguments":
    try expect_equal(
        arguments(), ["--list", "--repeat=2", "--timeout=0", "--", "--help"]
    )
