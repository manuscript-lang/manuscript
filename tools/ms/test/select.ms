// Choosing which of the tests a program lists run, and in what order.
import (
	seeded from "@std/random.ms",
	compile from "@std/regex.ms",
	expect_equal from "@std/test/test.ms",

	TestOptions from "./options.ms",
)

export type Plan:
	// Positions in the listing, in execution order, each `--repeat` round after the
	// previous one.
	order: List[Int] = []
	// Positions in the listing, once each, in the order one round runs them.
	selected: List[Int] = []
	// A test named with `--test` that the listing does not have, or empty.
	unknown: String = ""

// The error of the first of `--match` and `--exclude` that is not a regular expression.
export fn pattern_error(options: TestOptions) String?:
	for pattern in [options.matching.clone(), options.exclude.clone()]:
		compiled := compile(pattern)
		if compiled.is_error(): return compiled.err().message

	return none

// The tests of `available` that `options` select. `--test` names must match exactly,
// `--filter` is a substring and `--match` and `--exclude` are regular expressions; a
// selected test passes all of them.
export fn plan(available: List[String], options: TestOptions) Plan:
	var out = Plan()
	matching := compile(options.matching).get()
	exclude := compile(options.exclude).get()
	var found = List[Bool]()
	for _name in options.names: found.append(false)

	for at in 0..available.length():
		name := available[at]
		var exact = options.names.is_empty()

		for n in 0..options.names.length():
			if options.names[n] == name:
				exact = true
				found[n] = true

		if not exact: continue
		if not name.contains(options.filter): continue
		if not matching.matches(name): continue
		if not options.exclude.is_empty() and exclude.matches(name): continue

		out.selected.append(at)

	for n in 0..found.length():
		if not found[n]:
			out.unknown = options.names[n].clone()
			return out

	if seed := options.shuffle:
		var random = seeded(seed)
		out.selected = random.shuffle(out.selected.clone())

	rounds := if options.list: 1 else: options.repeat
	for _round in 0..rounds:
		for at in out.selected: out.order.append(at)
	return out

// The number of each test's file: files are numbered in the order of their first test,
// and a test's name is `file::test`.
export fn file_numbers(names: List[String]) List[Int]:
	var seen = List[String]()
	var out = List[Int]()

	for name in names:
		var file = name.clone()
		if parts := name.split_once("::"): file = parts.before.clone()

		var at = -1
		for n in 0..seen.length():
			if seen[n] == file: at = n

		if at < 0:
			seen.append(file)
			at = seen.length() - 1

		out.append(at)

	return out

test "selection by name, filter, pattern and exclusion":
	names := ["a.ms::one", "a.ms::two", "b.ms::one"]
	everything := plan(names, TestOptions())
	everything.selected | expect_equal(expected: [0, 1, 2])?

	var only = TestOptions()
	only.names = ["b.ms::one"]
	plan(names, only).selected | expect_equal(expected: [2])?

	var filtered = TestOptions()
	filtered.filter = "one"
	plan(names, filtered).selected | expect_equal(expected: [0, 2])?

	var matched = TestOptions()
	matched.matching = "^a"
	matched.exclude = "two"
	plan(names, matched).selected | expect_equal(expected: [0])?

test "an unknown name is reported and repeat rounds follow each other":
	names := ["a.ms::one", "a.ms::two"]
	var unknown = TestOptions()
	unknown.names = ["a.ms::nope"]
	plan(names, unknown).unknown | expect_equal(expected: "a.ms::nope")?

	var again = TestOptions()
	again.repeat = 2
	plan(names, again).order | expect_equal(expected: [0, 1, 0, 1])?

test "a shuffle keeps the same tests and repeats for a seed":
	names := ["a", "b", "c", "d", "e"]
	var options = TestOptions()
	options.shuffle = 7

	first := plan(names, options).selected
	second := plan(names, options).selected
	first | expect_equal(expected: second)?
	first.length() | expect_equal(expected: 5)?

test "files are numbered by their first test":
	file_numbers(["a.ms::x", "b.ms::y", "a.ms::z"]) | expect_equal(expected: [0, 1, 0])?
