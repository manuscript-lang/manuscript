import (
    expect_equal from "@std/test/test.ms",
    promise, wait_all from "@std/concurrency/promise.ms",
)

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn run(xs: List[Int], name: String) Int!:
    p := promise(fn: total(xs))
    q := promise(fn: ok(name.length()))
    return ok(try p.wait() + try q.wait())

test "a promise reads captures that are not scalars":
    xs := [1, 2, 3]
    both := wait_all([promise(fn: total(xs)), promise(fn: total(xs))])
    try expect_equal(both.get([]).length(), 2)
    try expect_equal(run(xs, "ab").get(0), 5)
