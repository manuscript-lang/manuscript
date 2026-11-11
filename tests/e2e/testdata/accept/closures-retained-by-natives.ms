import expect_equal from "@std/test/test.ms"

type Box:
	f: fn() String

fn churn(n: Int) Int:
	var t = 0

	for i in 0..n:
		z := "junk{i}" + "padding padding padding"
		t += z.length()

	return t

fn dflt(o: (fn() String)?, s: String) fn() String:
	return o.get(fn: s + "d")

fn mk(o: (fn() String)?, s: String) Box:
	h := o.get(fn: s + "x")
	return Box(f: h)

fn mk2(m: Map[Int, fn() String], s: String) List[fn() String]:
	var out = List[fn() String]()
	if m.get(7).is_none(): out.append(fn: s + "y")
	return out

fn inc(x: Int) Int: x + 1

fn build(r: fn(Int) Int) List[fn(Int) Int]:
	var out = List[fn(Int) Int]()

	// A stored function value has one owner: each closure a callback appends is its
	// own, and `r` moves into the list at its last use.
	[1, 2].for_each(fn i: out.append(fn x: x + i))
	out.append(r)
	return out

test "closures kept by natives own their captures":
	try expect_equal(dflt(none, "a")(), "ad")

	b := mk(none, "hello" + "world")
	c := churn(100)
	m := Map[Int, fn() String]()
	l := mk2(m, "abc" + "def")
	c2 := churn(100)
	try expect_equal(b.f() + l[0](), "helloworldxabcdefy")
	try expect_equal(c + c2 > 0, true)

	fs := build(inc)
	try expect_equal(fs.length(), 3)
	try expect_equal(fs[2](1), 2)

fn keep(r: fn(Int) Int) List[fn(Int) Int]:
	var out = List[fn(Int) Int]()
	out.append(r)
	return out

test "an escaping closure takes an explicit clone of a value that is used again":
	var a = [1, 2, 3]
	snapshot := a.clone()
	b := keep(fn x: x + snapshot.length())
	a.append(4)
	try expect_equal(b[0](1), 4)
	try expect_equal(a.length(), 4)
