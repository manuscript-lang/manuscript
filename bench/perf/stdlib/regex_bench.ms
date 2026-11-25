import (
	Regex, compile from "@std/regex.ms",
	expect_equal from "@std/test/test.ms",

	words from "./src/harness.ms",
)

// The helpers take what the fixture built, so the timing covers the regex work and its
// checks only.
fn captures_run(re Regex, text String, count Int) Int! {
	expected_row := ["word123", "word", "123"]
	rows := re.capture_all(text)?
	var checksum = 0

	for row in rows {
		expect_equal(row, expected_row)?
		for group in row {
			checksum += group.length()
		}
	}

	expect_equal(checksum, 14 * count)?
	return ok(checksum)
}

fn template_run(re Regex, text, expected, template String) Int! {
	out := re.replace_template(text, template)?
	expect_equal(out, expected)?
	return ok(out.length())
}

fn named_run(re Regex, expected Map[String, String]) Int {
	out := re.capture_named("abcdefgh")
	expect_equal(out, expected).get()
	return out.length()
}

fn named_pattern(count Int) String {
	return if count == 1 { "(?P<a>a)" } else { "(?P<a>a)(?P<b>b)(?P<c>c)(?P<d>d)(?P<e>e)(?P<f>f)(?P<g>g)(?P<h>h)" }
}

fn named_expected(count Int) Map[String, String] {
	names := ["a", "b", "c", "d", "e", "f", "g", "h"]
	var expected = Map[String, String]()
	for i in 0..count {
		expected.add(names[i].clone(), names[i].clone())
	}
	return expected
}

type BenchData {
	re Regex
	first, rest, text, expected_first, expected_rest, expected String
	re_12 Regex
	template String
	capture_re, template_re, literal_re Regex
	text_0, text_1, text_128, text_2000 String
	named_re_1, named_re_8 Regex
	named_1 Map[String, String]
	named_8 Map[String, String]
	text_15 String
	re_15, re_16 Regex
	text_17 String
	re_17 Regex
	expected_17 String
}

fn make_fixture() BenchData {
	re := compile("(a+)").get()
	first := "a".repeat(65536)
	rest := " a".repeat(1999)
	text := first + rest
	expected_first := "a".repeat(131072)
	expected_rest := " aa".repeat(1999)
	expected := expected_first + expected_rest
	re_12 := compile("x").get()
	template := "a".repeat(2000000)
	capture_re := compile("(word)([0-9]+)").get()
	template_re := compile("(?P<word>word)([0-9]+)").get()
	literal_re := compile("(word)([0-9]+)").get()
	text_0 := "word123 ".repeat(0)
	text_1 := "word123 ".repeat(1)
	text_128 := "word123 ".repeat(128)
	text_2000 := "word123 ".repeat(2000)
	named_re_1 := compile(named_pattern(1)).get()
	named_re_8 := compile(named_pattern(8)).get()
	named_1 := named_expected(1)
	named_8 := named_expected(8)
	text_15 := words(2000).join(" ")
	re_15 := compile("word[0-9]+").get()
	re_16 := compile("word[0-9]+").get()
	text_17 := words(2000).join(" ")
	re_17 := compile("word[0-9]+").get()
	expected_17 := ("w ".repeat(1999)) + "w"
	return BenchData(
		re: re,
		first: first,
		rest: rest,
		text: text,
		expected_first: expected_first,
		expected_rest: expected_rest,
		expected: expected,
		re_12: re_12,
		template: template,
		capture_re: capture_re,
		template_re: template_re,
		literal_re: literal_re,
		text_0: text_0,
		text_1: text_1,
		text_128: text_128,
		text_2000: text_2000,
		named_re_1: named_re_1,
		named_re_8: named_re_8,
		named_1: named_1,
		named_8: named_8,
		text_15: text_15,
		re_15: re_15,
		re_16: re_16,
		text_17: text_17,
		re_17: re_17,
		expected_17: expected_17,
	)
}

bench "regex.captures_all.0" {
	captures_run(fixture.capture_re, fixture.text_0, 0)?
}

bench "regex.captures_all.1" {
	captures_run(fixture.capture_re, fixture.text_1, 1)?
}

bench "regex.captures_all.128" {
	captures_run(fixture.capture_re, fixture.text_128, 128)?
}

bench "regex.captures_all.2000" {
	captures_run(fixture.capture_re, fixture.text_2000, 2000)?
}

bench "regex.replace_template.0" {
	template_run(
		fixture.template_re,
		fixture.text_0,
		"123:word$ ".repeat(0),
		"$2:${word}$$",
	)?
}

bench "regex.replace_template.1" {
	template_run(
		fixture.template_re,
		fixture.text_1,
		"123:word$ ".repeat(1),
		"$2:${word}$$",
	)?
}

bench "regex.replace_template.128" {
	template_run(
		fixture.template_re,
		fixture.text_128,
		"123:word$ ".repeat(128),
		"$2:${word}$$",
	)?
}

bench "regex.replace_template.2000" {
	template_run(
		fixture.template_re,
		fixture.text_2000,
		"123:word$ ".repeat(2000),
		"$2:${word}$$",
	)?
}

bench "regex.replace_template.mixed_long_short.2000" {
	out := fixture.re.replace_template(fixture.text, "$1$1")?
	expect_equal(out, fixture.expected)?
	out.length()
}

bench "regex.replace_template.literal.1" {
	template_run(fixture.literal_re, fixture.text_1, "fixed ".repeat(1), "fixed")?
}

bench "regex.replace_template.literal.2000" {
	template_run(fixture.literal_re, fixture.text_2000, "fixed ".repeat(2000), "fixed")?
}

bench "regex.replace_template.unused_large" {
	out := fixture.re_12.replace_template("z", fixture.template, 1)?
	expect_equal(out, "z")?
	out.length()
}

bench "regex.named_captures.1" {
	named_run(fixture.named_re_1, fixture.named_1)
}

bench "regex.named_captures.8" {
	named_run(fixture.named_re_8, fixture.named_8)
}

bench "regex.find_all" per 2000 {
	found := fixture.re_15.find_all(fixture.text_15)?
	expect_equal(found.length(), 2000)?
	found.length()
}

bench "regex.matches" per 10000 {
	var n = 0
	for i in 0..10000 {
		if fixture.re_16.matches("xx word123 yy") { n += 1 }
	}
	expect_equal(n, 10000)?
	n
}

bench "regex.replace_all" per 2000 {
	out := fixture.re_17.replace_all(fixture.text_17, "w")?
	expect_equal(out, fixture.expected_17)?
	out.length()
}
