import (
	JsonValue, parse from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

	inline_lines, render, with_lines from "./expect.ms",
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
