import (
    Promise,
    PromiseOptions,
    promise,
    wait_all,
    wait_first
) from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

fn spin(n: Int) Int:
    var s = 0
    for i in 0..n:
        s += i % 7
    return s

fn work(k: Int) Int!:
    return ok(spin(2000000) + k)

fn after(first: Promise[Int]) Int!:
    return ok(try first.wait() + 1)

fn make(k: Int) Promise[Int]!:
    return ok(promise(fn: work(k)))

// An idle thread may take a promise while the promises it uses belong to another thread's table, so these
// waits must not depend on where the work ran. Each shape is repeated so that some runs cross threads.
test "a promise waits on a promise made by another thread":
    base := spin(2000000)
    var total = 0

    for k in 0..12:
        first := promise(fn: work(k))
        second := promise(fn: after(first))
        total += try second.wait()

    try expect_equal(total, 12 * (base + 1) + 66)

test "a promise returned by a promise is waited by its caller":
    base := spin(2000000)
    var total = 0

    for k in 0..12:
        outer := promise(fn: make(k))
        inner := try outer.wait()
        total += try inner.wait()

    try expect_equal(total, 12 * base + 66)

test "wait_all and wait_first accept promises of several threads":
    base := spin(2000000)
    var inners = List[Promise[Int]]()

    for k in 0..6:
        outer := promise(fn: make(k))
        inners.append(try outer.wait())

    all := try wait_all(inners)
    try expect_equal(all.length(), 6)
    try expect_equal(all[5], base + 5)

    var more = List[Promise[Int]]()

    for k in 0..4:
        outer := promise(fn: make(k))
        more.append(try outer.wait())

    first := try wait_first(more)
    try expect_equal(first >= base, true)
