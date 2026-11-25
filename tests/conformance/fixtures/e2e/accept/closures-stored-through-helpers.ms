// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn store(var fs List[fn() Int], f fn() Int) Void {
	fs.append(f)
}

fn relay(var fs List[fn() Int], f fn() Int) Void {
	store(fs, f)
}

fn deep(var fs List[fn() Int], f fn() Int, n Int) Void {
	if n == 0 {
		relay(fs, f)
		return
	}

	deep(fs, f, n - 1)
}

fn keep[T](var xs List[T], move x T) Void {
	xs.append(x)
}

fn sum(fs List[fn() Int]) Int {
	var t = 0
	for f in fs {
		t += f()
	}
	return t
}

fn d1(text String) Int {
	var fs List[fn() Int] = []
	for p in text.split(",").collect().clone() {
		relay(fs, fn() Int => return p.length())
	}
	return sum(fs)
}

fn d2(text String) Int {
	var fs List[fn() Int] = []
	for p in text.split(",").collect().clone() {
		deep(fs, fn() Int => return p.length(), 3)
	}
	return sum(fs)
}

fn d3(text String) Int {
	var fs List[fn() Int] = []
	for p in text.split(",").collect().clone() {
		keep(fs, fn() Int => return p.length())
	}
	return sum(fs)
}

fn d4(text String) Int {
	var fs List[fn() Int] = []
	var i = 0

	for p in text.split(",").collect().clone() {
		n := p.length()
		at := i
		g := fn() Int => return n + at
		relay(fs, g)
		i += 1
	}

	return sum(fs)
}

fn d5(text String) Int {
	var fs List[fn() Int] = []

	for p in text.split(",").collect().clone() {
		g := fn() Int => return p.length()
		h := fn() Int => return g() + 1
		relay(fs, h)
	}

	return sum(fs)
}

test "a closure stored through helper functions owns its captures" {
	expect_equal(d1("x,yyyy,zz"), 7)?
	expect_equal(d2("x,yyyy,zz"), 7)?
	expect_equal(d3("x,yyyy,zz"), 7)?
	expect_equal(d4("x,yyyy,zz"), 10)?
	expect_equal(d5("x,yyyy,zz"), 10)?
}
