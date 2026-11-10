import (
	parse_int from "@std/math/math.ms",
	restrict from "@std/net/net.ms",
	run from "@std/os/process.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "restrict, parse_int and run take their defaults":
	network := try restrict(["example.com"])
	network.close()
	try expect_equal(try parse_int("42"), 42)

	output := try run("true").wait()
	try expect_true(output.exit_code == 0)
