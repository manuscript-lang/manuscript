import (
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	case_names, checksum, summarize from "./strappend_table.ms",
)

fn sample(trial: Int, version: String, elapsed: Int) List[String]:
	return case_names().map(
		fn name: "{trial} {version} {name} {elapsed} # {checksum(name)}"
	)

test "minima and reordered samples":
	lines := sample(0, "ms", 200).concat(
		sample(0, "rust", 100)
	).concat(sample(1, "ms", 50)).concat(sample(1, "rust", 100))
	result := expect_ok(summarize(lines.reversed(), 2))?
	expect_equal(result.split("0.50x").length() - 1, case_names().length())?

test "invalid evidence":
	valid := sample(0, "ms", 100).concat(sample(0, "rust", 100))
	rest := valid.slice(1, valid.length()).get([])
	cases := [
		List[String](), valid.slice(0, valid.length() - 1).get([]),
		valid.concat([valid[0].clone()]), sample(0, "ms", 100),
		[valid[0].replace("# 40000000", "# -1")].concat(rest),
		sample(0, "ms", 0).concat(sample(0, "rust", 100)),
		sample(0, "ms", -1).concat(sample(0, "rust", 100)),
		[valid[0].replace("100 #", "nan #")].concat(rest)
	]
	for lines in cases:
		_cause := expect_error(summarize(lines, 1))?

	_short := expect_error(summarize(valid, 2))?
