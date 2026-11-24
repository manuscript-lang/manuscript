// conform: tags=testing,tier-io
// conform: phase=test
import (
	expect_equal from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

fn tick() Void! {
	return sleep(milliseconds(1)).wait()
}

type Inner {
	tags List[String]
	weights Map[String, Int]
}

type Outer {
	inner Inner
	history List[Inner]
	title String
}

fn var Inner.bump(key String) Void! {
	tick()?
	self.tags.append(key.clone())
	self.weights[key.clone()] = (self.weights.get(key) or 0) + 1
}

fn var Outer.touch(key String) Void! {
	self.inner.bump(key)?
	tick()?
	self.history.append(
		Inner(
			tags: self.inner.tags.clone(),
			weights: self.inner.weights.clone(),
		)
	)
}

fn fresh(title String) Outer {
	return Outer(
		inner: Inner(tags: [], weights: Map[String, Int]()),
		history: [],
		title: title.clone(),
	)
}

test "nested var methods through two levels of fields" {
	var o = fresh("t")
	o.touch("a")?
	o.touch("b")?
	o.touch("a")?
	expect_equal(o.history.length(), 3)?
}

fn consume(move o Outer) Int! {
	tick()?

	var n = o.history.length()

	for h in o.history {
		tick()?
		n += h.tags.length()
	}

	return ok(n)
}

test "a moved outer consumed across parks" {
	var o = fresh("m")
	o.touch("x")?
	o.touch("y")?
	expect_equal(consume(o)?, 5)?
}

fn take_inner(var o Outer) Inner! {
	tick()?

	var inner = o.inner.clone()
	inner.tags.append("taken")
	tick()?
	return ok(inner)
}

test "a field moved out of a var parameter then returned" {
	var o = fresh("v")
	o.touch("k")?

	got := take_inner(o)?
	expect_equal(got.tags.length(), 2)?
}

fn swap(var a Outer, var b Outer) Void! {
	tick()?

	held := a.inner.clone()
	a.inner = b.inner.clone()
	tick()?
	b.inner = held.clone()
}

test "two var parameters swapping fields across a park" {
	var a = fresh("a")
	var b = fresh("b")
	a.touch("1")?
	b.touch("2")?
	b.touch("3")?
	swap(a, b)?
	expect_equal(a.inner.tags.length(), 2)?
}
