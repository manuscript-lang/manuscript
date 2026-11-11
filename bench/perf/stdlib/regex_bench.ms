import (
	compile from "@std/string.ms",
	keep, measure from "@std/test/bench.ms",
	expect_equal from "@std/test/test.ms",

	words from "./src/harness.ms",
)

fn captures_bench(count: Int) Result[Unit, Error]:
	re := compile("(word)([0-9]+)")?
	text := "word123 ".repeat(count)?
	expected_row := ["word123", "word", "123"]

	fn work() Result[Unit, Error]:
		rows := re.captures_all(text)?
		var checksum = 0

		for row in rows:
			expect_equal(row, expected_row)?
			for group in row:
				checksum += group.length()

		expect_equal(checksum, 14 * count)?
		return keep(checksum)

	return measure(1, work)

fn template_bench(count: Int) Result[Unit, Error]:
	re := compile("(?P<word>word)([0-9]+)")?
	text := "word123 ".repeat(count)?
	expected := "123:word$ ".repeat(count)?

	fn work() Result[Unit, Error]:
		out := re.replace_template(text, "$2:$\{word\}$$")?
		expect_equal(out, expected)?
		return keep(out.length())

	return measure(1, work)

bench "regex.captures_all.0":
	captures_bench(0)?

bench "regex.captures_all.1":
	captures_bench(1)?

bench "regex.captures_all.128":
	captures_bench(128)?

bench "regex.captures_all.2000":
	captures_bench(2000)?

bench "regex.replace_template.0":
	template_bench(0)?

bench "regex.replace_template.1":
	template_bench(1)?

bench "regex.replace_template.128":
	template_bench(128)?

bench "regex.replace_template.2000":
	template_bench(2000)?

bench "regex.replace_template.mixed_long_short.2000":
	re := compile("(a+)")?
	first := "a".repeat(65536)?
	rest := " a".repeat(1999)?
	text := first + rest
	expected_first := "a".repeat(131072)?
	expected_rest := " aa".repeat(1999)?
	expected := expected_first + expected_rest

	fn work() Result[Unit, Error]:
		out := re.replace_template(text, "$1$1")?
		expect_equal(out, expected)?
		return keep(out.length())

	measure(1, work)?

fn literal_template_bench(count: Int) Result[Unit, Error]:
	re := compile("(word)([0-9]+)")?
	text := "word123 ".repeat(count)?
	expected := "fixed ".repeat(count)?

	fn work() Result[Unit, Error]:
		out := re.replace_template(text, "fixed")?
		expect_equal(out, expected)?
		return keep(out.length())

	return measure(1, work)

bench "regex.replace_template.literal.1":
	literal_template_bench(1)?

bench "regex.replace_template.literal.2000":
	literal_template_bench(2000)?

bench "regex.replace_template.unused_large":
	re := compile("x")?
	template := "a".repeat(2000000)?

	fn work() Result[Unit, Error]:
		out := re.replace_template("z", template, 1)?
		expect_equal(out, "z")?
		return keep(out.length())

	measure(1, work)?

fn named_bench(count: Int) Result[Unit, Error]:
	pattern := if count == 1: "(?P<a>a)" else: "(?P<a>a)(?P<b>b)(?P<c>c)(?P<d>d)(?P<e>e)(?P<f>f)(?P<g>g)(?P<h>h)"
	re := compile(pattern)?
	names := ["a", "b", "c", "d", "e", "f", "g", "h"]
	var expected = Map[String, String]()
	for i in 0..count:
		expected.add(names[i].clone(), names[i].clone())

	fn work() Result[Unit, Error]:
		out := re.named_captures("abcdefgh")
		expect_equal(out, expected)?
		return keep(out.length())

	return measure(1, work)

bench "regex.named_captures.1":
	named_bench(1)?

bench "regex.named_captures.8":
	named_bench(8)?

bench "regex.find_all":
	text := words(2000).join(" ")
	re := compile("word[0-9]+")?

	fn work() Result[Unit, Error]:
		found := re.find_all(text)?
		expect_equal(found.length(), 2000)?
		return keep(found.length())

	measure(2000, work)?

bench "regex.matches":
	re := compile("word[0-9]+")?

	fn work() Result[Unit, Error]:
		var n = 0
		for i in 0..10000:
			if re.matches("xx word123 yy"): n += 1
		expect_equal(n, 10000)?
		return keep(n)

	measure(10000, work)?

bench "regex.replace_all":
	text := words(2000).join(" ")
	re := compile("word[0-9]+")?
	expected := ("w ".repeat(1999)?) + "w"

	fn work() Result[Unit, Error]:
		out := re.replace_all(text, "w")?
		expect_equal(out, expected)?
		return keep(out.length())

	measure(2000, work)?
