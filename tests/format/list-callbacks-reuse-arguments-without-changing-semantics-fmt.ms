// conform: tags=closures,control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/list-callbacks-reuse-arguments-without-changing-semantics.ms
import expect_true from "@std/test/test.ms"

fn keep(var list List[fn() Int], value Int) Void {
	list.append(value: fn() Int => value)
	return
}

fn grow(var list List[Int], value Int) Int {
	list.append(value: value)
	return value
}

fn nested(items List[Int]) List[Int] {
	return items.map(
		fn(value Int) Int => (
			items.map(fn(inner Int) Int => inner + value).length()
			+ value
		)
	)
}

test "list callbacks" {
	var items = List[Int]()
	var i = 0

	while i < 5 {
		items.append(value: i)
		i += 1
	}

	doubled := items.map(fn(value Int) Int => value * 2)
	expect_true((doubled[4] == 8))?

	even := items.filter(fn(value Int) Bool => value % 2 == 0)
	expect_true((even.length() == 3))?
	expect_true(
		(
			items.fold(
				initial: 0,
				step: fn(accumulator Int, value Int) Int => (
					accumulator
					+ value
				)
			) == 10
		)
	)?
	expect_true((items.count(predicate: fn(value Int) Bool => value > 1) == 3))?

	var retained = List[fn() Int]()
	for value in items {
		keep(list: retained, value: value)
	}

	called := retained.map(fn(value fn() Int) Int => value())
	expect_true(
		(
			called.fold(
				initial: 0,
				step: fn(accumulator Int, value Int) Int => (
					accumulator
					+ value
				)
			) == 10
		)
	)?

	var grown = List[Int]()
	grown.append(value: 1)
	grown.append(value: 2)

	var seen = List[Int]()
	for value in grown.clone() {
		seen.append(value: grow(list: grown, value: value))
	}
	expect_true((seen.length() == 2 and grown.length() == 4))?
	expect_true((nested(items: items)[2] == 7))?
}
// expect-format: rewritten
// expect-formatted: import expect_true from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: fn keep(var list List[fn() Int], value Int) Void {
// expect-formatted: \tlist.append(value: fn() Int => value)
// expect-formatted: \treturn
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn grow(var list List[Int], value Int) Int {
// expect-formatted: \tlist.append(value: value)
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn nested(items List[Int]) List[Int] {
// expect-formatted: \treturn items.map(
// expect-formatted: \t\tfn(value Int) Int => (
// expect-formatted: \t\t\titems.map(fn(inner Int) Int => inner + value).length()
// expect-formatted: \t\t\t+ value
// expect-formatted: \t\t)
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "list callbacks" {
// expect-formatted: \tvar items = List[Int]()
// expect-formatted: \tvar i = 0
// expect-formatted:
// expect-formatted: \twhile i < 5 {
// expect-formatted: \t\titems.append(value: i)
// expect-formatted: \t\ti += 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tdoubled := items.map(fn(value Int) Int => value * 2)
// expect-formatted: \texpect_true((doubled[4] == 8))?
// expect-formatted:
// expect-formatted: \teven := items.filter(fn(value Int) Bool => value % 2 == 0)
// expect-formatted: \texpect_true((even.length() == 3))?
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\titems.fold(
// expect-formatted: \t\t\t\tinitial: 0,
// expect-formatted: \t\t\t\tstep: fn(accumulator, value Int) Int => (
// expect-formatted: \t\t\t\t\taccumulator
// expect-formatted: \t\t\t\t\t+ value
// expect-formatted: \t\t\t\t)
// expect-formatted: \t\t\t) == 10
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted: \texpect_true((items.count(predicate: fn(value Int) Bool => value > 1) == 3))?
// expect-formatted:
// expect-formatted: \tvar retained = List[fn() Int]()
// expect-formatted: \tfor value in items {
// expect-formatted: \t\tkeep(list: retained, value: value)
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tcalled := retained.map(fn(value fn() Int) Int => value())
// expect-formatted: \texpect_true(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tcalled.fold(
// expect-formatted: \t\t\t\tinitial: 0,
// expect-formatted: \t\t\t\tstep: fn(accumulator, value Int) Int => (
// expect-formatted: \t\t\t\t\taccumulator
// expect-formatted: \t\t\t\t\t+ value
// expect-formatted: \t\t\t\t)
// expect-formatted: \t\t\t) == 10
// expect-formatted: \t\t)
// expect-formatted: \t)?
// expect-formatted:
// expect-formatted: \tvar grown = List[Int]()
// expect-formatted: \tgrown.append(value: 1)
// expect-formatted: \tgrown.append(value: 2)
// expect-formatted:
// expect-formatted: \tvar seen = List[Int]()
// expect-formatted: \tfor value in grown.clone() {
// expect-formatted: \t\tseen.append(value: grow(list: grown, value: value))
// expect-formatted: \t}
// expect-formatted: \texpect_true((seen.length() == 2 and grown.length() == 4))?
// expect-formatted: \texpect_true((nested(items: items)[2] == 7))?
// expect-formatted: }
