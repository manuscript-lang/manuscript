import (
	expect_equal, expect_true from "@std/test/test.ms",
	new_renderer from "./markdown.ms",
)

test "complete lines render and the partial tail waits":
	var r = new_renderer()
	first := r.feed("# Title\nhel")
	try expect_true(first.contains("Title"))
	try expect_true(not first.contains("hel"))

	rest := r.feed("lo **bold**\n")
	try expect_true(rest.contains("hello"))
	try expect_equal(r.finish(), "")

test "fenced code is boxed and keeps its text verbatim":
	var r = new_renderer()
	out := r.feed("```ms\nx := **1**\n```\n")
	try expect_true(out.contains("x := **1**"))
	try expect_true(out.contains("┌─ ms"))
	try expect_true(out.contains("└─"))

test "finish flushes an unterminated line":
	var r = new_renderer()
	_none := r.feed("- item")
	try expect_true(r.finish().contains("• item"))
