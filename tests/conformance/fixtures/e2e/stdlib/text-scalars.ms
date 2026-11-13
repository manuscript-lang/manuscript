// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	expect_equal from "@std/test/test.ms",
	scalars from "@std/text.ms",
)

fn read_all(text: String) List[String]!:
	var out: List[String] = []
	var scalars = scalars(text)
	for scalar in scalars:
		out.append(scalar)
	return ok(out)

test "a scalar stream yields every scalar width in order and matches chars":
	for text in ["", "abc", "héllo wörld", "日本語", "a🙂b🙂", "e\u{301}x"]:
		expect_equal(read_all(text)?, text.chars())?

test "a long non-ASCII scan is linear":
	text := "héllo wörld ünï ".repeat(6250).get("")
	var found = 0
	for scalar in scalars(text):
		if scalar == "ö": found += 1
	expect_equal(found, 6250)?
