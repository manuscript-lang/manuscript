import (
	expect_equal from "@std/test/test.ms",

	Echo from "./first.ms",
	Quiet from "./second.ms",
)

// Both types declare `run` with the same default; `first.ms` is padded so its node ids
// differ from `second.ms`, and each omitted argument must still take its own method's
// default.
test "an omitted argument takes the default of its own operation":
	echoed := Echo(3).run("fake", [])?
	expect_equal(echoed.exit_code, 3)?
	expect_equal(echoed.stdout.length(), 0)?

	quiet := Quiet(4).run("fake", [])?
	expect_equal(quiet.exit_code, 4)?
