// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn make(i Int) Int! {
	if i % 5 == 0 { return error(Error("bad")) }
	return ok(i)
}

// A Result built on each arm and tested after the join.
fn total(n Int) Int {
	var total = 0

	for i in 0..n {
		var r Int! = ok(0)

		if i % 2 == 0 {
			r = make(i)
		} else {
			r = make(i + 1)
		}

		if v := r { total += v }
	}

	return total
}

fn pick(flag Bool, a Int) Int? {
	var o Int? = null
	if flag { o = a }

	v := o
	if v != null { return v + 1 }

	return null
}

test "a Result tested after an if/else join" {
	expect_equal(total(20), 160)?
}

test "an optional tested after a join" {
	expect_equal(pick(true, 4), 5)?
	expect_equal(pick(false, 4), null)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
