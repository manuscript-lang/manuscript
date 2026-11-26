// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Counter {
	n Int
}

fn var Counter.bump(by Int = 1) Int {
	self.n += by
	return self.n
}

interface Stepper {
	var fn step() Int
}

fn var Counter.step() Int {
	self.n += 10
	return self.n
}

fn drain(var xs List[Int]) Void {
	push := xs.append
	push(7)
	push(8)
}

fn each(f fn(move Int) Void) Void {
	f(100)
}

test "a method value that changes its receiver borrows the variable" {
	var xs = [1, 2, 3]
	reverse := xs.reverse
	reverse()

	add := xs.append
	add(9)
	expect_equal(xs, [3, 2, 1, 9])?

	var counter = Counter(n: 0)
	bump := counter.bump
	bump()
	bump(by: 5)
	expect_equal(counter.n, 6)?

	var names = Map[String, Int]()
	put := names.add
	put("a", 1)
	expect_equal(names.keys(), ["a"])?
}

test "the variable is shared through calls and callbacks" {
	var xs = [1]
	drain(xs)
	each(xs.append)
	expect_equal(xs, [1, 7, 8, 100])?

	pop := xs.pop
	pop()
	expect_equal(xs, [1, 7, 8])?
}

test "an interface method value shares the underlying value" {
	var counter = Counter(n: 0)
	var view Stepper = counter
	step := view.step
	step()
	step()
	expect_equal(view.step(), 30)?
}

test "a list method value appends to the list" {
	var names List[String] = []
	append := names.append
	append("a")
	append("b")
	names | expect_equal(["a", "b"])?
}
// expect-exit: 0
// expect-tests: passed=4 failed=0
