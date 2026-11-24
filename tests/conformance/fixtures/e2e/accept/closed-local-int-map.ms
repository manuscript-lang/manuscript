// conform: tags=closures,control-flow,faults,lists,maps,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/closed-local-int-map.ms
import (
	panic from "@std/core.ms",
	expect_contains,
	expect_equal,
	expect_false,
	expect_fault,
	expect_true from "@std/test/test.ms",
)

fn effect(var visits List[Int], value Int) Int:
	visits.append(value)
	return value

fn missing() Int:
	values := Map[Int, Int]()
	return values.get(0) or panic("called Optional.get() on null")

fn returned_alias() Map[Int, Int]:
	var values = Map[Int, Int]()
	values.add(2, 20)
	return values

test "closed maps preserve lookup replacement and absence":
	var values = Map[Int, Int]()
	values.length() | expect_equal(0)?
	values.contains(7) | expect_false?
	(values.get(7) == null) | expect_true?
	values.add(7, 10)
	values.add(7, 20)
	values.add(-1, 30)
	values.length() | expect_equal(2)?
	values.contains(7) | expect_true?
	(values.get(7) or panic("called Optional.get() on null")) | expect_equal(20)?
	(values.get(-1) or panic("called Optional.get() on null")) | expect_equal(30)?
	values.get_or(0, 99) | expect_equal(99)?

test "closed map arguments retain written evaluation order":
	var visits List[Int] = []
	var values = Map[Int, Int]()
	values.add(value: effect(visits, 20), key: effect(visits, 2))
	values.add(key: effect(visits, 3), value: effect(visits, 30))
	visits | expect_equal([20, 2, 3, 30])?
	(values.get(2) or panic("called Optional.get() on null")) | expect_equal(20)?
	(values.get(3) or panic("called Optional.get() on null")) | expect_equal(30)?

test "missing local lookups keep Optional faults":
	(expect_fault(fn: _ignored := missing())?) | expect_contains("Optional.get")?

test "escaped map results keep insertion order":
	var values = returned_alias()
	values.add(1, 10)
	values.add(2, 21)

	var seen List[Int] = []
	for entry in values:
		seen.append(entry.key)
	seen | expect_equal([2, 1])?
	(values.get(2) or panic("called Optional.get() on null")) | expect_equal(21)?

test "captured maps read the entries present at capture":
	var values = Map[Int, Int]()
	values.add(1, 10)

	callback := fn() Int: values.get(1) or panic("called Optional.get() on null")
	callback() | expect_equal(10)?
