// conform: tags=closures,control-flow,faults,interpolation,lists,modules,mutation,numbers,optional,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/inlined-list-callbacks-keep-semantics.ms
import expect_true from "@std/test/test.ms"

type Point:
	x: Int

test "inlined callbacks":
	var items = List[Int]()
	var i = 0

	while i < 5:
		items.append(value: i)
		i += 1

	offset := 10
	shifted := items.map(fn(v: Int) Int: v + offset)
	expect_true((shifted.length() == 5 and shifted.get(index: 4) == 14))?

	labels := items.map(fn(v: Int) String: "n{v}")
	expect_true((labels.get(index: 2) == "n2"))?

	floats := items.map(fn(v: Int) Float: 0.5)
	expect_true((floats.length() == 5))?

	points := items.map(fn(v: Int) Point: Point(x: v))
	expect_true((points.get(index: 3) == Point(x: 3)))?

	evens := items.filter(fn(v: Int) Bool: v % 2 == 0)
	expect_true((evens.length() == 3))?
	expect_true((points.filter(fn(p: Point) Bool: p.x > 2).length() == 2))?
	expect_true((items.fold(initial: 0, step: fn(a: Int, v: Int) Int: a + v) == 10))?
	expect_true(
		(
			items.fold(
				initial: "", step: fn(a: String, v: Int) String: (a + "{v}")
			) == "01234"
		)
	)?
	expect_true((items.count(predicate: fn(v: Int) Bool: v > 1) == 3))?
	expect_true((items.any(predicate: fn(v: Int) Bool: v == 4)))?
	expect_true((not items.any(predicate: fn(v: Int) Bool: v == 9)))?
	expect_true((items.all(predicate: fn(v: Int) Bool: v < 5)))?
	expect_true((not items.all(predicate: fn(v: Int) Bool: v < 4)))?

	// Closures cannot mutate captures, so iterate a clone while growing the original.
	var seen = List[Int]()

	for v in items.clone():
		items.append(value: 100)
		seen.append(value: v)

	expect_true((seen.length() == 5 and items.length() == 10))?
	expect_true((List[Int]().map(fn(v: Int) Int: v).length() == 0))?
	expect_true(
		(
			items.map(
				fn(v: Int) Int: (
					items
					.filter(fn(w: Int) Bool: w == v)
					.length()
				)
			).length() == 10
		)
	)?
