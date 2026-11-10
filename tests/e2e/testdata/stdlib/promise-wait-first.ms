import (
    deferred,
    complete,
    promise,
    wait_first,
    PromiseOptions from "@std/concurrency/promise.ms",
    milliseconds, sleep, monotonic from "@std/time.ms",
    expect_equal, expect_error, expect_true from "@std/test/test.ms",
)

fn immediate(id: Int) Unit:
    complete[Int](id, ok(1))

fn delayed(id: Int) Unit:
    let _ = sleep(milliseconds(5000)).wait()
    complete[Int](id, ok(1))

test "wait_first prefers an already completed input over unstarted deferred work":
    let pending = deferred[Int](immediate)
    let ready = promise(fn: ok(2))
    while not ready.done():
        let _ = sleep(milliseconds(1)).wait()
    try expect_equal((try wait_first([pending, ready])), 2)

test "wait_first propagates a deferred promise construction limit":
    let pending = deferred[Int](delayed).with(
        options: PromiseOptions(timeout: milliseconds(20))
    )
    let start = monotonic()
    let reason = wait_first([pending]) | try expect_error
    try expect_equal(reason.kind, "ETIMEDOUT")
    try expect_true(monotonic().difference(start).to_milliseconds() < 2000)
