// conform: tags=closures,control-flow,faults,formatter,interpolation,lists,modules,mutation,numbers,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/inlined-list-callbacks-keep-semantics.ms
import expect_true from "@std/test/test.ms"

type Point {
	x Int
}

test "inlined callbacks" {
	var items = List[Int]()
	var i = 0

	while i < 5 {
		items.append(value: i)
		i += 1
	}

	offset := 10
	shifted := items.map(fn(v Int) Int => v + offset)
	expect_true((shifted.length() == 5 and shifted[4] == 14))?

	labels := items.map(fn(v Int) String => f"n{v}")
	expect_true((labels[2] == "n2"))?

	floats := items.map(fn(v Int) Float => 0.5)
	expect_true((floats.length() == 5))?

	points := items.map(fn(v Int) Point => Point(x: v))
	expect_true((points[3] == Point(x: 3)))?

	evens := items.filter(fn(v Int) Bool => v % 2 == 0)
	expect_true((evens.length() == 3))?
	expect_true((points.filter(fn(p Point) Bool => p.x > 2).length() == 2))?
	expect_true((items.fold(initial: 0, step: fn(a Int, v Int) Int => a + v) == 10))?
	expect_true(
		(
			items.fold(
				initial: "",
				step: fn(a String, v Int) String => (a + f"{v}")
			) == "01234"
		)
	)?
	expect_true((items.count(predicate: fn(v Int) Bool => v > 1) == 3))?
	expect_true((items.any(predicate: fn(v Int) Bool => v == 4)))?
	expect_true((not items.any(predicate: fn(v Int) Bool => v == 9)))?
	expect_true((items.all(predicate: fn(v Int) Bool => v < 5)))?
	expect_true((not items.all(predicate: fn(v Int) Bool => v < 4)))?

	// Closures cannot mutate captures, so iterate a clone while growing the original.
	var seen = List[Int]()

	for v in items.clone() {
		items.append(value: 100)
		seen.append(value: v)
	}

	expect_true((seen.length() == 5 and items.length() == 10))?
	expect_true((List[Int]().map(fn(v Int) Int => v).length() == 0))?
	expect_true(
		(
			items.map(
				fn(v Int) Int => (
					items
					.filter(fn(w Int) Bool => w == v)
					.length()
				)
			).length() == 10
		)
	)?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Point {
// expect-formatted: \tx Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "inlined callbacks" {
// expect-formatted: \tvar items = List[Int]()
// expect-formatted: \tvar i = 0
// expect-formatted:
// expect-formatted: \twhile i < 5 {
// expect-formatted: \t\titems.append(value: i)
// expect-formatted: \t\ti += 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \toffset := 10
// expect-formatted: \tshifted := items.map(fn(v Int) Int => v + offset)
// expect-formatted: \texpect_true((shifted.length() == 5 and shifted[4] == 14))?
// expect-formatted:
// expect-formatted: \tlabels := items.map(fn(v Int) String => f"n{v}")
// expect-formatted: \texpect_true((labels[2] == "n2"))?
// expect-formatted:
// expect-formatted: \tfloats := items.map(fn(v Int) Float => 0.5)
// expect-formatted: \texpect_true((floats.length() == 5))?
// expect-formatted:
// expect-formatted: \tpoints := items.map(fn(v Int) Point => Point(x: v))
// expect-formatted: \texpect_true((points[3] == Point(x: 3)))?
// expect-formatted:
// expect-formatted: \tevens := items.filter(fn(v Int) Bool => v % 2 == 0)
// expect-formatted: \texpect_true((evens.length() == 3))?
// expect-formatted: \texpect_true((points.filter(fn(p Point) Bool => p.x > 2).length() == 2))?
// expect-formatted: \texpect_true((items.fold(initial: 0, step: fn(a, v Int) Int => a + v) == 10))?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\titems.fold(
// expect-formatted: \t\t\t\tinitial: "",
// expect-formatted: \t\t\t\tstep: fn(a String, v Int) String => (a + f"{v}")
// expect-formatted: \t\t\t) == "01234"
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: \texpect_true((items.count(predicate: fn(v Int) Bool => v > 1) == 3))?
// expect-formatted: \texpect_true((items.any(predicate: fn(v Int) Bool => v == 4)))?
// expect-formatted: \texpect_true((not items.any(predicate: fn(v Int) Bool => v == 9)))?
// expect-formatted: \texpect_true((items.all(predicate: fn(v Int) Bool => v < 5)))?
// expect-formatted: \texpect_true((not items.all(predicate: fn(v Int) Bool => v < 4)))?
// expect-formatted:
// expect-formatted: \t// Closures cannot mutate captures, so iterate a clone while growing the original.
// expect-formatted: \tvar seen = List[Int]()
// expect-formatted:
// expect-formatted: \tfor v in items.clone() {
// expect-formatted: \t\titems.append(value: 100)
// expect-formatted: \t\tseen.append(value: v)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \texpect_true((seen.length() == 5 and items.length() == 10))?
// expect-formatted: \texpect_true((List[Int]().map(fn(v Int) Int => v).length() == 0))?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\titems.map(
// expect-formatted: \t\t\t\tfn(v Int) Int => (
// expect-formatted: \t\t\t\t\titems
// expect-formatted: \t\t\t\t\t.filter(fn(w Int) Bool => w == v)
// expect-formatted: \t\t\t\t\t.length()
// expect-formatted: \t\t\t\t)
// expect-formatted: \t\t\t).length() == 10
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: }
