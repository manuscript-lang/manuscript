import (
	JsonValue, parse from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

	inline_lines, render, render_phase, with_lines from "./expect.ms",
)

fn observed(text String) JsonValue {
	return parse(text).get_or(JsonValue.Null)
}

test "a diagnostic renders as one line with its position" {
	report := observed(
		"{\"exit_code\":1,\"diagnostics\":[{\"code\":\"MS3000\",\"message\":\"a\\nb\",\"position\":{\"line\":9,\"column\":3}}]}"
	)
	expect_equal(render(report), ["expect-error: MS3000 9:3 a\\nb"])?
}

test "a clean check states its exit code" {
	report := observed("{\"exit_code\":0,\"diagnostics\":[]}")
	expect_equal(render(report), ["expect-exit: 0"])?
}

test "a span and a fix are kept" {
	report := observed(
		"{\"exit_code\":1,\"diagnostics\":[{\"code\":\"MS1000\",\"message\":\"m\",\"position\":{\"line\":3,\"column\":13},\"end\":{\"line\":3,\"column\":14},\"fix\":{\"position\":{\"line\":3,\"column\":13},\"end\":{\"line\":3,\"column\":14},\"replacement\":\":=\"}}]}"
	)
	expect_equal(
		render(report),
		["expect-error: MS1000 3:13-3:14 m", "expect-fix: 3:13-3:14 \":=\""],
	)?
}

test "lines written after a program are read back and replaced" {
	program := "// conform: phase=check\nexport fn main() Int { return 0 }\n"
	once := with_lines(program, ["expect-exit: 0"])
	expect_equal(inline_lines(once), ["expect-exit: 0"])?

	twice := with_lines(once, ["expect-error: MS1 1:1 x"])
	expect_equal(inline_lines(twice), ["expect-error: MS1 1:1 x"])?
	expect_equal(twice.starts_with(program), true)?
}

test "run lines carry exit, output and a partial marker" {
	report := observed("{\"exit_code\":3,\"stdout\":\"a\\n\\nb\",\"stderr\":\"\"}")
	expect_equal(
		render_phase("run", report),
		[
			"expect-exit: 3", "expect-stdout: a", "expect-stdout:", "expect-stdout: b",
			"expect-stdout-partial"
		],
	)?
}

test "test lines carry the summary counts" {
	report := observed(
		"{\"exit_code\":1,\"stderr\":\"\",\"report\":{\"summary\":{\"passed\":4,\"failed\":1}}}"
	)
	expect_equal(
		render_phase("test", report),
		["expect-exit: 1", "expect-tests: passed=4 failed=1"],
	)?
}

test "parse lines say whether fmt leaves the program alone" {
	report := observed("{\"diagnostics\":[],\"unchanged\":true}")
	expect_equal(render_phase("parse", report), ["expect-format: unchanged"])?
}
