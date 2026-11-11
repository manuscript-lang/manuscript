import arguments from "@std/os/env.ms"
import expect_equal from "@std/test/test.ms"

test "arguments":
    expect_equal(
        arguments(), ["--list", "--repeat=2", "--timeout=0", "--", "--help"]
    )?
