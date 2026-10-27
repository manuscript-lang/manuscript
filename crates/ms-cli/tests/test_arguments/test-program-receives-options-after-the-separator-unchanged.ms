from "@std/process.ms" import arguments
from "@std/testing.ms" import expect_equal

test "arguments":
    try expect_equal(arguments(), ["--list", "--repeat=2", "--timeout=0", "--", "--help"])
