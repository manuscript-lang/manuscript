import (
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	commands, layout_problems, parse_groups from "./perf_groups.ms",
)

TEXT := "# c\nsuite | programs | time | sh run.sh {n} | suite/results.md\nweb | io | time | ms run a.ms -- {n} | -\nx | io | probe | - | x/README.md\n"

test "parse and argv" {
	groups := expect_ok(parse_groups(TEXT))?
	expect_equal(groups.length(), 3)?
	expect_equal(
		commands(groups[1], "/bin/ms", 7),
		[["/bin/ms", "run", "a.ms", "--", "7"]],
	)?
	expect_equal(groups[1].results, "")?
	expect_equal(commands(groups[2], "/bin/ms", 7).length(), 0)?

	chained := expect_ok(parse_groups("c | io | time | ms a.ms ;; sh b.sh {n} | -"))?
	expect_equal(commands(chained[0], "/m", 2), [["/m", "a.ms"], ["sh", "b.sh", "2"]])?
}

test "bad lines" {
	_a := expect_error(parse_groups("a | io | time | x"))?
	_b := expect_error(parse_groups("a | io | fast | x | -"))?
	_c := expect_error(parse_groups("a | io | probe | - | -\na | io | probe | - | -"))?
}

test "layout" {
	groups := expect_ok(parse_groups(TEXT))?
	ok := layout_problems(groups, ["README.md", "groups.txt", "suite", "web", "x"])
	expect_equal(ok.length(), 0)?

	bad := layout_problems(groups, ["suite", "stray", "web", "x"])
	expect_equal(bad.length(), 1)?
}
