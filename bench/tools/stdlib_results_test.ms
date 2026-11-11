import (
	expect_contains, expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	parse_sample from "./compare_stdlib.ms",
	Ran, must from "./lib.ms",
	stdlib_table from "./stdlib_bench.ms",
	Stats, case_labels, read_cases from "./stdlib_results.ms",
)

fn bench(name: String, status: String, ops: String, median: String) String:
	return j(
		"<'name':'m.ms::{name}','status':'{status}','stats':<'operations':{ops},'median_ns':{median}>>"
	)

fn j(text: String) String:
	return text.replace("'", "\"").replace("<", "\{").replace(">", "\}")

fn document(cases: List[String]) String:
	return j("<'benches':[{cases.join(",")}],'diagnostics':[]>")

test "invalid numeric fields are rejected":
	texts := [
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':1,'samples':3,'median_ns':'2'>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':1,'samples':3,'median_ns':-1>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':1,'samples':3,'median_ns':null>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':0,'median_ns':2>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':1.5,'median_ns':2>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':0,'median_ns':2>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'samples':true,'median_ns':2>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'median_ns':2,'min_ns':-1>>]>"
		),
		j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'median_ns':2,'min_ns':1,'max_ns':1>>]>"
		)
	]
	for text in texts:
		_cause := expect_error(read_cases(text))?

test "huge exponents and non-finite constants are rejected, finite zero is not":
	for token in ["1e999", "NaN", "Infinity", "-Infinity"]:
		text := j(
			"<'benches':[<'name':'a','status':'passed','stats':<'operations':1,'median_ns':{token}>>]>"
		)
		_cause := expect_error(read_cases(text))?

	cases := expect_ok(
		read_cases(
			j(
				"<'benches':[<'name':'a','status':'passed','stats':<'operations':1,'median_ns':0>>]>"
			)
		)
	)?
	expect_equal(
		cases[0].stats.get(
			Stats(0, none, none, -1.0, none, none, none, none)
		).median_ns,
		0.0
	)?

test "labels disambiguate only collisions":
	labels := case_labels(["a.ms::x", "b.ms::x", "b.ms::y"])
	expect_equal(labels.get_or("a.ms::x", ""), "a.ms::x")?
	expect_equal(labels.get_or("b.ms::x", ""), "b.ms::x")?
	expect_equal(labels.get_or("b.ms::y", ""), "y")?

test "a user label cannot collide with a qualified display name":
	names := ["a.ms::x", "b.ms::x", "c.ms::a.ms::x"]
	labels := case_labels(names)
	for name in names:
		expect_equal(labels.get_or(name, ""), name)?

test "reads operations and median per case":
	sample := expect_ok(
		parse_sample(
			document(
				[
					bench("a", "passed", "10", "2.5"), bench("b", "passed", "1", "0")
				]
			),
			none
		)
	)?
	expect_equal(sample.operations.get_or("m.ms::a", 0), 10)?
	expect_equal(sample.medians.get_or("m.ms::a", 0.0), 2.5)?
	expect_equal(sample.medians.get_or("m.ms::b", 1.0), 0.0)?

test "qualified case identity":
	before := document([bench("a", "passed", "10", "2")])
	first := expect_ok(parse_sample(before, none))?
	other := before.replace("m.ms::a", "other.ms::a")
	_changed := expect_error(parse_sample(other, first.operations.clone()))?
	both := expect_ok(
		parse_sample(
			document(
				[
					bench("a", "passed", "10", "2"),
					j(
						"<'name':'other.ms::a','status':'passed','stats':<'operations':10,'median_ns':2>>"
					)
				]
			),
			none
		)
	)?
	expect_equal(both.operations.length(), 2)?

test "changed cases or operation counts are rejected":
	first := expect_ok(parse_sample(document([bench("a", "passed", "10", "2")]), none))?
	changes := [
		document([bench("a", "passed", "11", "2")]),
		document([bench("b", "passed", "10", "2")]),
		document(
			[
				bench("a", "passed", "10", "2"), bench("b", "passed", "1", "2")
			]
		)
	]
	for text in changes:
		_cause := expect_error(parse_sample(text, first.operations.clone()))?

test "failed, duplicate, empty or uncompiled runs are rejected":
	texts := [
		document([bench("a", "failed", "10", "2")]),
		document(
			[
				bench("a", "passed", "10", "2"), bench("a", "passed", "10", "2")
			]
		),
		document([]),
		j("<'benches':[],'diagnostics':[<'message':'does not compile'>]>")
	]
	for text in texts:
		_cause := expect_error(parse_sample(text, none))?

test "impossible measurements are rejected":
	for text in [
		document([bench("a", "passed", "0", "2")]),
		document([bench("a", "passed", "10", "-1")])
	]:
		_cause := expect_error(parse_sample(text, none))?

test "a failed producer yields no report":
	failed := Ran(
		true, 42, "{document([bench("a", "passed", "10", "2")])}", "producer detail"
	)
	_cause := expect_error(must("producer", failed))?
	empty := expect_error(stdlib_table(document([])))?
	expect_contains(empty.message, "no cases")?
