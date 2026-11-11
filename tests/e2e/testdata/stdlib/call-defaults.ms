import (
	parse_int from "@std/math/math.ms",
	restrict from "@std/net/net.ms",
	run from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "restrict, parse_int and run take their defaults":
	network := restrict(["example.com"])?
	network.close()
	expect_equal(parse_int("42")?, 42)?

	output := run("true").wait()?
	expect_true(output.exit_code == 0)?
