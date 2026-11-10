import (
    Promise,
    PromiseOptions,
    promise,
    complete,
    deferred,
    wait_all,
    wait_first from "@std/concurrency/promise.ms",
    expect_equal from "@std/test/test.ms",
    sleep from "@std/time.ms",
)

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
    let base = spin(2000000)
    var total = 0

    for k in 0..12:
        let first = promise(fn: work(k))
        let second = promise(fn: after(first))
        total += try second.wait()

    try expect_equal(total, 12 * (base + 1) + 66)

test "a promise returned by a promise is waited by its caller":
    let base = spin(2000000)
    var total = 0

    for k in 0..12:
        let outer = promise(fn: make(k))
        let inner = try outer.wait()
        total += try inner.wait()

    try expect_equal(total, 12 * base + 66)

test "wait_all and wait_first accept promises of several threads":
    let base = spin(2000000)
    var inners = List[Promise[Int]]()

    for k in 0..6:
        let outer = promise(fn: make(k))
        inners.append(try outer.wait())

    let all = try wait_all(inners)
    try expect_equal(all.length(), 6)
    try expect_equal(all[5], base + 5)

    var more = List[Promise[Int]]()

    for k in 0..4:
        let outer = promise(fn: make(k))
        more.append(try outer.wait())

    let first = try wait_first(more)
    try expect_equal(first >= base, true)

fn long_sleep() Promise[Unit]!:
    return ok(sleep(60.seconds()))

fn deferred_error() Promise[Unit]!:
    return ok(
        deferred[Unit](
            fn id: complete[Unit](id, error(Error("should stay deferred")))
        )
    )

test "wait_first runs a local deferred input beside a foreign promise":
    for k in 0..8:
        let outer = promise(fn: long_sleep())

        // Give idle threads work to take while this thread computes; the result is checked.
        let busy = spin(2000000)
        try expect_equal(busy >= 0, true)

        let remote = (try outer.wait()).with(
            options: PromiseOptions(timeout: 1.seconds())
        )
        let local = deferred[Unit](fn id: complete[Unit](id, ok(unit)))
        try wait_first([local, remote])

test "wait_first returns a ready input before foreign deferred work":
    for k in 0..8:
        let outer = promise(fn: deferred_error())
        let busy = spin(2000000)
        try expect_equal(busy >= 0, true)

        let remote = try outer.wait()
        let ready = promise[Unit](fn: ok(unit))
        while not ready.done():
            continue
        try wait_first([remote, ready])
