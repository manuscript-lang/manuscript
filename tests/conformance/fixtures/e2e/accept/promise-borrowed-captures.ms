// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	promise, wait_all from "@std/concurrency/promise.ms",
	expect_equal from "@std/test/test.ms",
)

fn total(xs List[Int]) Int!:
	return ok(xs.length())

fn run(xs List[Int], name String) Int!:
	p := promise(() => total(xs))
	q := promise(() => ok(name.length()))
	return ok(p.wait()? + q.wait()?)

test "a promise reads captures that are not scalars":
	xs := [1, 2, 3]
	both := wait_all([promise(() => total(xs)), promise(() => total(xs))])
	expect_equal(both.get_or([]).length(), 2)?
	expect_equal(run(xs, "ab").get_or(0), 5)?
