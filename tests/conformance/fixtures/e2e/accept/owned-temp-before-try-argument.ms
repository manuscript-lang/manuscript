// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

// A temporary that owns a resource, followed by a `try` in a later argument of the same
// call, is moved into the consumed parameter rather than copied.
interface Gate:
	var fn put(value: Int) Unit!
	var fn close() Unit!

type Door:
	unused: Bool = false

fn var Door.put(value: Int) Unit!:
	return ok(unit)

fn var Door.close() Unit!:
	return ok(unit)

type Holder:
	gate: Gate

fn var Holder.close() Unit!:
	return self.gate.close()

fn make() Holder!:
	return ok(Holder(Door()))

fn both(first: Holder, second: Holder) Int!:
	var a = first
	var b = second
	a.gate.put(1)?
	b.gate.put(2)?
	return ok(2)

test "a held temporary is consumed by the call":
	count := both(Holder(Door()), make()?)?
	expect_equal(count, 2)?
