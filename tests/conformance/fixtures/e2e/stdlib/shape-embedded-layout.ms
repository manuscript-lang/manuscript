// conform: tags=testing,tier-stdlib
// conform: phase=test
import parse, stringify from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

// A value stored inside an optional, a Result or an enum payload has its leaves where the host puts them, not where its own
// layout does, so a Bool before an Int moves the Int. Text, JSON and equality must read the leaves where they are.
type Mixed {
	flag Bool
	count Int
	tail Bool
	small Int32
}

type Holder {
	first Bool
	inner Mixed
	maybe Int?
}

type Opt {
	maybe Int?
	name String = ""
}

enum Shape {
	Mark(inner Mixed)
	Run(a Int, b Bool, c Int)
}

fn mixed(count Int) Mixed {
	return Mixed(flag: true, count: count, tail: false, small: 5)
}

fn holder() Holder {
	return Holder(first: true, inner: mixed(99), maybe: 4)
}

fn found(count Int) Mixed? {
	return mixed(count)
}

fn made(count Int) Mixed! {
	return ok(mixed(count))
}

test "an optional holds a record whose leaves differ in size" {
	expect_equal(f"{found(99)}", "some(Mixed(count: 99, flag: true, small: 5, tail: false))")?
	expect_equal(found(99) == found(99), true)?
	expect_equal(found(99) == found(98), false)?
}

test "a Result holds a record whose leaves differ in size" {
	expect_equal(f"{made(99)}", "ok(Mixed(count: 99, flag: true, small: 5, tail: false))")?
	expect_equal(stringify(found(99))?, "{\"flag\":true,\"count\":99,\"tail\":false,\"small\":5}")?
}

test "a record holds a record and an optional after a Bool" {
	expect_equal(f"{holder()}", "Holder(first: true, inner: Mixed(count: 99, flag: true, small: 5, tail: false), maybe: some(4))")?
	text := stringify(holder())?
	expect_equal(text, "{\"first\":true,\"inner\":{\"flag\":true,\"count\":99,\"tail\":false,\"small\":5},\"maybe\":4}")?
	expect_equal(parse[Holder](text)? == holder(), true)?
}

test "a Result holds a record with an optional field" {
	result Result[Opt, Error] := ok(Opt(maybe: 80))
	expect_equal(f"{result}", "ok(Opt(maybe: some(80), name: \"\"))")?
	flagged Result[Int?, Error] := ok(5)
	expect_equal(f"{flagged}", "ok(some(5))")?
}

test "an enum payload holds a record whose leaves differ in size" {
	mark Shape := Shape.Mark(inner: mixed(99))
	expect_equal(f"{mark}", "Shape.Mark(Mixed(count: 99, flag: true, small: 5, tail: false))")?
	run Shape := Shape.Run(a: 1, b: true, c: 3)
	expect_equal(f"{run}", "Shape.Run(1, true, 3)")?
	expect_equal(mark == Shape.Mark(inner: mixed(99)), true)?
	expect_equal(mark == Shape.Mark(inner: mixed(98)), false)?
}
