import (
	expect_equal from "@std/test/test.ms",

	greeting from "./src/lib.ms",
)

test "greeting":
	expect_equal(greeting("ms"), "Hello, ms")?
