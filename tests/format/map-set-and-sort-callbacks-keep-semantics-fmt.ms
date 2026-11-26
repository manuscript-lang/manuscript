// conform: tags=closures,faults,formatter,lists,modules,optional,parser,stdlib-testing,strings,testing,tier-core,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/map-set-and-sort-callbacks-keep-semantics.ms
import expect_true from "@std/test/test.ms"

fn byLength(left String, right String) Int => left.length() - right.length()

fn record(var into List[Int], value Int) Void {
	into.append(value: value)
	return
}

test "map callbacks" {
	m := {"a": 1, "bb": 2, "ccc": 3}
	sums := m.map(fn(key String, value Int) Int => key.length() + value)
	expect_true((sums.get("bb") == 4))?
	expect_true((m.filter(fn(key String, value Int) Bool => value > 1).length() == 2))?
	expect_true(
		(
			m.fold(
				initial: 0,
				step: fn(
					accumulator Int,
					key String,
					value Int,
				) Int => (accumulator + value)
			) == 6
		)
	)?
	expect_true(
		(
			m.fold_right(
				initial: 0,
				step: fn(
					accumulator Int,
					key String,
					value Int,
				) Int => (accumulator * 10 + value)
			) == 321
		)
	)?

	var visited = List[Int]()
	m.for_each(fn(key String, value Int) Void => record(into: visited, value: value))
}

test "set callbacks" {
	s := [1, 2, 3].to_set()
	expect_true((s.map(fn(value Int) Int => value % 2).length() == 2))?
	expect_true((s.filter(fn(value Int) Bool => value > 1).length() == 2))?
	expect_true(
		(
			s.fold(
				initial: 0,
				step: fn(accumulator Int, value Int) Int => (
					accumulator
					+ value
				)
			) == 6
		)
	)?
	expect_true(
		(
			s.fold_right(
				initial: 0,
				step: fn(accumulator Int, value Int) Int => (
					accumulator * 10
					+ value
				)
			) == 321
		)
	)?
}

test "sort with a comparator" {
	words := ["ccc", "a", "bb"]
	sorted := words.sorted(compare: byLength)
	expect_true((sorted[0] == "a" and sorted[2] == "ccc"))?

	closure := words.sorted(
		compare: fn(left String, right String) Int => (
			right.length()
			- left.length()
		)
	)
	expect_true((closure[0] == "ccc"))?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn byLength(left, right String) Int => left.length() - right.length()
// expect-formatted:
// expect-formatted: fn record(var into List[Int], value Int) Void {
// expect-formatted: \tinto.append(value: value)
// expect-formatted: \treturn
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "map callbacks" {
// expect-formatted: \tm := {"a": 1, "bb": 2, "ccc": 3}
// expect-formatted: \tsums := m.map(fn(key String, value Int) Int => key.length() + value)
// expect-formatted: \texpect_true((sums.get("bb") == 4))?
// expect-formatted: \texpect_true((m.filter(fn(key String, value Int) Bool => value > 1).length() == 2))?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tm.fold(
// expect-formatted: \t\t\t\tinitial: 0,
// expect-formatted: \t\t\t\tstep: fn(
// expect-formatted: \t\t\t\t\taccumulator Int,
// expect-formatted: \t\t\t\t\tkey String,
// expect-formatted: \t\t\t\t\tvalue Int,
// expect-formatted: \t\t\t\t) Int => (accumulator + value)
// expect-formatted: \t\t\t) == 6
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tm.fold_right(
// expect-formatted: \t\t\t\tinitial: 0,
// expect-formatted: \t\t\t\tstep: fn(
// expect-formatted: \t\t\t\t\taccumulator Int,
// expect-formatted: \t\t\t\t\tkey String,
// expect-formatted: \t\t\t\t\tvalue Int,
// expect-formatted: \t\t\t\t) Int => (accumulator * 10 + value)
// expect-formatted: \t\t\t) == 321
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted:
// expect-formatted: \tvar visited = List[Int]()
// expect-formatted: \tm.for_each(fn(key String, value Int) Void => record(into: visited, value: value))
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "set callbacks" {
// expect-formatted: \ts := [1, 2, 3].to_set()
// expect-formatted: \texpect_true((s.map(fn(value Int) Int => value % 2).length() == 2))?
// expect-formatted: \texpect_true((s.filter(fn(value Int) Bool => value > 1).length() == 2))?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\ts.fold(
// expect-formatted: \t\t\t\tinitial: 0,
// expect-formatted: \t\t\t\tstep: fn(accumulator, value Int) Int => (
// expect-formatted: \t\t\t\t\taccumulator
// expect-formatted: \t\t\t\t\t+ value
// expect-formatted: \t\t\t\t)
// expect-formatted: \t\t\t) == 6
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\ts.fold_right(
// expect-formatted: \t\t\t\tinitial: 0,
// expect-formatted: \t\t\t\tstep: fn(accumulator, value Int) Int => (
// expect-formatted: \t\t\t\t\taccumulator * 10
// expect-formatted: \t\t\t\t\t+ value
// expect-formatted: \t\t\t\t)
// expect-formatted: \t\t\t) == 321
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "sort with a comparator" {
// expect-formatted: \twords := ["ccc", "a", "bb"]
// expect-formatted: \tsorted := words.sorted(compare: byLength)
// expect-formatted: \texpect_true((sorted[0] == "a" and sorted[2] == "ccc"))?
// expect-formatted:
// expect-formatted: \tclosure := words.sorted(
// expect-formatted: \t\tcompare: fn(left, right String) Int => (right.length() - left.length())
// expect-formatted: \t)
// expect-formatted: \texpect_true((closure[0] == "ccc"))?
// expect-formatted: }
