import (
	Regex, compile from "@std/regex.ms",
	expect_equal from "@std/test/test.ms",
)

fn rows_run(re Regex, text String, expected List[String], count, width Int) Int! {
	rows := re.capture_all(text)?
	expect_equal(rows.length(), count)?

	var checksum = 0

	for row in rows {
		expect_equal(row, expected)?
		for group in row {
			checksum += group.length()
		}
	}

	expect_equal(checksum, count * width)?
	return ok(checksum)
}

fn first_run(re Regex, text String, expected List[String]) Int! {
	out := re.capture(text)
	expect_equal(out, expected)?
	return ok(out.length())
}

fn names_run(re Regex, text String, expected Map[String, String]) Int! {
	out := re.capture_named(text)
	expect_equal(out, expected)?
	return ok(out.length())
}

fn id_map(present Bool) Map[String, String] {
	var expected = Map[String, String]()
	if present { expected.add("id", "123") }
	return expected
}

fn last_map(present Bool) Map[String, String] {
	var expected = Map[String, String]()
	if present { expected.add("last", "x") }
	return expected
}

type BenchData {
	re Regex
	text String
	expected List[List[String]]
	re_8, re_9 Regex
	text_9 String
	re_13 Regex
	text_13 String
	expected_13 List[String]
	plain_re, grouped_re Regex
	whole_expected List[String]
	grouped_expected List[String]
	none_expected List[String]
	text_0, text_1, text_128, text_2000, text_1000g String
	named_re, anon_re, late_re Regex
	long_miss String
	id_hit Map[String, String]
	no_names Map[String, String]
	late_hit Map[String, String]
}

fn make_fixture() BenchData {
	re := compile("a+").get()
	text := "a".repeat(65536)
	expected := [[text.clone()]]
	re_8 := compile("a*").get()
	re_9 := compile("word[0-9]+").get()
	text_9 := "word123 ".repeat(2000)
	re_13 := compile("a+").get()
	text_13 := "a".repeat(65536)
	expected_13 := [text_13.clone()]
	plain_re := compile("word[0-9]+").get()
	grouped_re := compile("(word)([0-9]+)").get()
	whole_expected := ["word123"]
	grouped_expected := ["word123", "word", "123"]
	none_expected List[String] := []
	text_0 := "word123 ".repeat(0)
	text_1 := "word123 ".repeat(1)
	text_128 := "word123 ".repeat(128)
	text_2000 := "word123 ".repeat(2000)
	text_1000g := "word123"
	named_re := compile("word(?P<id>[0-9]+)").get()
	anon_re := compile("(word)([0-9]+)").get()
	late_re := compile(("(a?)".repeat(128)) + "(?P<last>x)").get()
	long_miss := "z".repeat(65536)
	id_hit := id_map(true)
	no_names := id_map(false)
	late_hit := last_map(true)
	return BenchData(
		re: re.clone(),
		text: text,
		expected: expected,
		re_8: re_8.clone(),
		re_9: re_9.clone(),
		text_9: text_9,
		re_13: re_13.clone(),
		text_13: text_13,
		expected_13: expected_13,
		plain_re: plain_re.clone(),
		grouped_re: grouped_re.clone(),
		whole_expected: whole_expected,
		grouped_expected: grouped_expected,
		none_expected: none_expected,
		text_0: text_0,
		text_1: text_1,
		text_128: text_128,
		text_2000: text_2000,
		text_1000g: text_1000g,
		named_re: named_re.clone(),
		anon_re: anon_re.clone(),
		late_re: late_re.clone(),
		long_miss: long_miss,
		id_hit: id_hit,
		no_names: no_names,
		late_hit: late_hit,
	)
}

bench "regex.cardinality.whole.0" {
	rows_run(fixture.plain_re, fixture.text_0, fixture.whole_expected, 0, 7)?
}

bench "regex.cardinality.whole.1" {
	rows_run(fixture.plain_re, fixture.text_1, fixture.whole_expected, 1, 7)?
}

bench "regex.cardinality.whole.128" {
	rows_run(fixture.plain_re, fixture.text_128, fixture.whole_expected, 128, 7)?
}

bench "regex.cardinality.whole.2000" {
	rows_run(fixture.plain_re, fixture.text_2000, fixture.whole_expected, 2000, 7)?
}

bench "regex.cardinality.grouped.1" {
	rows_run(fixture.grouped_re, fixture.text_1, fixture.grouped_expected, 1, 14)?
}

bench "regex.cardinality.grouped.2000" {
	rows_run(fixture.grouped_re, fixture.text_2000, fixture.grouped_expected, 2000, 14)?
}

bench "regex.cardinality.whole.long" {
	rows := fixture.re.capture_all(fixture.text, 1)?
	expect_equal(rows, fixture.expected)?
	rows[0][0].length()
}

bench "regex.cardinality.whole.empty_matches" {
	rows := fixture.re_8.capture_all("a🙂🙂a", 3)?
	expect_equal(rows, [["a"], [""], ["a"]])?
	rows.length()
}

bench "regex.cardinality.whole.over_limit" {
	out := fixture.re_9.capture_all(fixture.text_9, 1)
	expected Result[List[List[String]], Error] := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	expect_equal(out, expected)?
	out.is_error()
}

bench "regex.cardinality.first.whole.hit" {
	first_run(fixture.plain_re, fixture.text_1000g, fixture.whole_expected)?
}

bench "regex.cardinality.first.whole.miss" {
	first_run(fixture.plain_re, "none", fixture.none_expected)?
}

bench "regex.cardinality.first.grouped.hit" {
	first_run(fixture.grouped_re, fixture.text_1000g, fixture.grouped_expected)?
}

bench "regex.cardinality.first.whole.long" {
	out := fixture.re_13.capture(fixture.text_13)
	expect_equal(out, fixture.expected_13)?
	out[0].length()
}

bench "regex.cardinality.named.whole.hit" {
	names_run(fixture.plain_re, fixture.text_1000g, fixture.no_names)?
}

bench "regex.cardinality.named.whole.long_miss" {
	names_run(fixture.plain_re, fixture.long_miss, fixture.no_names)?
}

bench "regex.cardinality.named.named.hit" {
	names_run(fixture.named_re, fixture.text_1000g, fixture.id_hit)?
}

bench "regex.cardinality.named.anonymous.hit" {
	names_run(fixture.anon_re, fixture.text_1000g, fixture.no_names)?
}

bench "regex.cardinality.named.anonymous.long_miss" {
	names_run(fixture.anon_re, fixture.long_miss, fixture.no_names)?
}

bench "regex.cardinality.named.late.hit" {
	names_run(fixture.late_re, "x", fixture.late_hit)?
}

bench "regex.cardinality.named.late.miss" {
	names_run(fixture.late_re, "z", fixture.no_names)?
}
