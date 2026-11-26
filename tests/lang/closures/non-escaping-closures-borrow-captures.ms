// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

// A closure that does not outlive its maker reads what it captures in place; one that
// is returned or stored owns a copy and keeps the value it was made with.
type Matrix {
	data List[Int]
	label String
}

fn total(m Matrix, f fn(Int) Int) Int {
	var sum = 0
	for x in m.data {
		sum += f(x)
	}
	return sum
}

fn scaled(m Matrix) Int {
	return total(m, x => x + m.data.length())
}

fn nested(m Matrix, names List[String]) Int {
	outer := fn(x Int) Int {
		inner := fn(y Int) Int {
			return y + m.data.length() + names.length()
		}
		return inner(x)
	}

	return total(m, outer)
}

fn push(var out List[Int], n Int) Void {
	out.append(n)
}

fn each(f fn(Int) Void) Void {
	f(1)
	f(2)
	f(3)
}

fn collect() List[Int] {
	var out List[Int] = []
	each(i => push(out, i))
	return out
}

fn make_reader() fn() Int {
	var tags = ["a"]
	tags.append("b")
	return () => tags.length()
}

type Box {
	f fn() Int
}

fn lit(text String) Int {
	var t = 0

	for p in text.split(",").collect().clone() {
		fs := [fn() Int => return p.length()]
		t += fs[0]()
	}

	return t
}

fn keep_rec(text String) List[Box] {
	var out List[Box] = []
	for p in text.split(",").collect().clone() {
		out.append(Box(f: fn() Int => return p.length()))
	}
	return out
}

fn keep_map(text String) Int {
	var m Map[Int, fn() Int] = {}
	var i = 0

	for p in text.split(",").collect().clone() {
		m.add(i, fn() Int => return p.length())
		i += 1
	}

	var t = 0
	for k in m.keys() {
		t += (m.get(k) or panic("called Optional.get() on null"))()
	}
	return t
}

fn keep_opt(text String) Int {
	var os List[(fn() Int)?] = []
	for p in text.split(",").collect().clone() {
		os.append((fn() Int => return p.length()))
	}

	var t = 0
	for o in os {
		t += (o or panic("called Optional.get() on null"))()
	}
	return t
}

fn store(var fs List[fn() Int], f fn() Int) Void {
	fs.append(f)
}

fn keep_user(text String) Int {
	var fs List[fn() Int] = []
	for p in text.split(",").collect().clone() {
		store(fs, fn() Int => return p.length())
	}

	var t = 0
	for f in fs {
		t += f()
	}
	return t
}

fn stored_total(text String) Int {
	var t = lit(text)
	for b in keep_rec(text) {
		t += b.f()
	}
	return t + keep_map(text) + keep_opt(text) + keep_user(text)
}

test "closure stored by a call keeps what it captured" {
	expect_equal(stored_total("x,yyyy,zz"), 35)?
}

test "non-escaping closure reads its capture" {
	m := Matrix(data: [1, 2, 3], label: "m")
	expect_equal(scaled(m), 15)?
	expect_equal(nested(m, ["x", "y"]), 21)?
}

test "closure made in a loop sees each iteration" {
	var results List[Int] = []

	for i in [1, 2, 3] {
		var names List[String] = []
		for unused in 0..i {
			names.append("n")
		}

		count := () => names.length()
		results.append(count())
	}

	expect_equal(results, [1, 2, 3])?
}

test "closure passes a captured var on without copying" {
	expect_equal(collect(), [1, 2, 3])?
}

test "escaping closure keeps its own value" {
	read := make_reader()
	expect_equal(read(), 2)?
}
// expect-exit: 0
// expect-tests: passed=5 failed=0
