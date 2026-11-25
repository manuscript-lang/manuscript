// conform: tags=closures,generics,lists,stdlib-property,stdlib-testing,testing,tier-io,try-result
// conform: phase=test
import (
	panic from "@std/core.ms",
	PropertyOptions,
	bools,
	check,
	constant,
	element_of,
	floats,
	ints,
	lists,
	one_of,
	optionals,
	pairs,
	strings from "@std/test/property.ms",
	expect_contains, expect_equal, expect_error, expect_true from "@std/test/test.ms",
)

test "a true property passes" {
	check(
		"reverse twice",
		lists(ints(-100, 100)),
		xs => expect_equal(xs.reversed().reversed(), xs),
	)?
}

test "a failing list property shrinks to the smallest list" {
	cause := expect_error(
		check(
			"small sums",
			lists(ints(0, 1000)),
			xs => expect_true(xs.sum() < 50),
			PropertyOptions(seed: 11),
		)
	)?
	expect_contains(cause.message, "counterexample: [50]")?
}

test "a failing integer property shrinks toward the boundary" {
	cause := expect_error(
		check(
			"below ten",
			ints(-1000, 1000),
			n => expect_true(n < 10),
			PropertyOptions(seed: 3),
		)
	)?
	expect_contains(cause.message, "counterexample: 10\n")?
}

test "negative values shrink toward zero" {
	cause := expect_error(
		check(
			"above minus ten",
			ints(-1000, 1000),
			n => expect_true(n > -10),
			PropertyOptions(seed: 5),
		)
	)?
	expect_contains(cause.message, "counterexample: -10\n")?
}

test "strings shrink to the offending character" {
	cause := expect_error(
		check(
			"no z",
			strings("abz", 12),
			s => expect_true(not s.contains("z")),
			PropertyOptions(seed: 2),
		)
	)?
	expect_contains(cause.message, "counterexample: z\n")?
}

test "pairs shrink both components" {
	cause := expect_error(
		check(
			"small pair sum",
			pairs(ints(-50, 50), ints(-50, 50)),
			p => expect_true(p.first + p.second < 10),
			PropertyOptions(seed: 1),
		)
	)?
	expect_contains(cause.message, "counterexample: Pair(first: ")?
}

test "optionals shrink toward the failing payload" {
	cause := expect_error(
		check(
			"below seven",
			optionals(ints(0, 100)),
			o => expect_true((o or 0) < 7),
			PropertyOptions(seed: 9),
		)
	)?
	expect_contains(cause.message, "counterexample: some(7)")?
}

test "filtered generators only produce kept values" {
	check("even", ints(0, 1000).filter(n => n % 2 == 0), n => expect_equal(n % 2, 0))?
}

test "zip and flat_map compose generators" {
	sums := ints(0, 9).zip(ints(0, 9), (a, b) => a + b)
	check("sum bound", sums, n => expect_true(n >= 0 and n <= 18))?

	sized := ints(1, 3).flat_map(n => lists(ints(0, 9), n, n))
	check(
		"length follows the drawn size",
		sized,
		xs => expect_true(xs.length() >= 1 and xs.length() <= 3),
	)?
}

test "mapped, one_of, element_of, constant, floats and bools compose" {
	doubled := ints(0, 10).map(n => n * 2)
	check("doubled is even", doubled, n => expect_equal(n % 2, 0))?
	check(
		"choice",
		one_of([constant(1), constant(2)]),
		n => expect_true(n == 1 or n == 2),
	)?
	check("element", element_of(["a", "b"]), s => expect_true(s == "a" or s == "b"))?
	check("unit interval", floats(0.0, 1.0), f => expect_true(f >= 0.0 and f <= 1.0))?
	check("bool", bools(), b => expect_true(b or not b))?
}

test "floats spanning the whole finite range stay inside it" {
	widest := 1.7976931348623157e308
	check(
		"wide floats",
		floats(0.0 - widest, widest),
		f => expect_true(f >= 0.0 - widest and f <= widest),
		PropertyOptions(runs: 300, seed: 1),
	)?
	check(
		"equal bounds",
		floats(0.1, 0.1),
		f => expect_true(f == 0.1),
		PropertyOptions(runs: 50, seed: 1),
	)?
}

test "the same seed reproduces the same failure" {
	first := expect_error(
		check(
			"seeded",
			lists(ints(0, 100)),
			xs => expect_true(xs.length() < 3),
			PropertyOptions(seed: 42),
		)
	)?
	second := expect_error(
		check(
			"seeded",
			lists(ints(0, 100)),
			xs => expect_true(xs.length() < 3),
			PropertyOptions(seed: 42),
		)
	)?
	expect_equal(first.message, second.message)?
	expect_contains(first.message, "counterexample: [0, 0, 0]")?
}

test "a fault inside a property shrinks like an error" {
	cause := expect_error(
		check(
			"no big values",
			ints(0, 1000),
			n => faults_at(n, 100),
			PropertyOptions(seed: 4),
		)
	)?
	expect_contains(cause.message, "counterexample: 100\n")?
	expect_contains(cause.message, "fault:")?
}

fn faults_at(n Int, limit Int) Void! {
	if n >= limit {
		panic("too big")
	}
}
