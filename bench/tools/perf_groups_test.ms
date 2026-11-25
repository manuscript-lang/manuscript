import (
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	argv, layout_problems, parse_groups from "./perf_groups.ms",
)

TEXT := "# c\nsuite | time | sh run.sh {n} | suite/results.md\nweb | time | ms run a.ms -- {n} | -\nx | probe | - | x/README.md\n"

test "parse and argv" {
	groups := expect_ok(parse_groups(TEXT))?
	expect_equal(groups.length(), 3)?
	expect_equal(argv(groups[1], "/bin/ms", 7), ["/bin/ms", "run", "a.ms", "--", "7"])?
	expect_equal(groups[1].results, "")?
	expect_equal(argv(groups[2], "/bin/ms", 7).length(), 0)?
}

test "bad lines" {
	_a := expect_error(parse_groups("a | time | x"))?
	_b := expect_error(parse_groups("a | fast | x | -"))?
	_c := expect_error(parse_groups("a | probe | - | -\na | probe | - | -"))?
}

test "layout" {
	groups := expect_ok(parse_groups(TEXT))?
	ok := layout_problems(groups, ["old"], ["README.md", "suite", "old", "web", "x"])
	expect_equal(ok.length(), 0)?

	bad := layout_problems(groups, ["gone"], ["suite", "stray", "web", "x"])
	expect_equal(bad.length(), 2)?
}
