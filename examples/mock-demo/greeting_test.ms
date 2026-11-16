import (
	expect_equal from "@std/test/test.ms",

	NOW_TEXT from "./fake_clock.ms",
	NAME from "./fake_store.ms",
	banner from "./greeting.ms",
)

test "banner uses the fake clock and store":
	expect_equal(banner()?, f"hello {NAME}, it is {NOW_TEXT}")?
