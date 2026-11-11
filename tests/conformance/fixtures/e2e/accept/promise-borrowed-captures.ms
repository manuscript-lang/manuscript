// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	promise, wait_all from "@std/concurrency/promise.ms",
	expect_equal from "@std/test/test.ms",
)

fn total(xs: List[Int]) Int!:
	return ok(xs.length())

fn run(xs: List[Int], name: String) Int!:
	p := promise(fn: total(xs))
	q := promise(fn: ok(name.length()))
	return ok(p.wait()? + q.wait()?)

test "a promise reads captures that are not scalars":
	xs := [1, 2, 3]
	both := wait_all([promise(fn: total(xs)), promise(fn: total(xs))])
	expect_equal(both.get([]).length(), 2)?
	expect_equal(run(xs, "ab").get(0), 5)?
