import panic from "@std/core.ms"
import (
    promise,
    wait_all,
    wait_first,
    PromiseOptions,
    cancel_switch
) from "@std/concurrency/promise.ms"
import (expect_equal, expect_error, expect_ok, expect_true) from "@std/test/test.ms"
import milliseconds, nanoseconds, sleep from "@std/os/time.ms"

fn report(reason: Error) String:
    if reason.kind == "EIO":
        return reason.details["report"].split("\n").get(0).clone()

    return reason.message.clone()

fn forever() Int:
    for i in 0..600:
        let _ = sleep(milliseconds(100)).wait()
    return 0

test "a fault inside a promise ends only that promise":
    let broken = promise(fn: ok(panic("promise fault")))
    let fine = promise(fn: ok(7))
    let reason = broken.wait() | try expect_error
    report(reason) | try expect_equal("promise fault")
    fine.wait() | try expect_ok | try expect_equal(7)

test "a timed out wait reports Timeout and cancels the work":
    let slow = promise(
        fn: ok(forever()), options: PromiseOptions(timeout: milliseconds(20))
    )
    let reason = slow.wait() | try expect_error
    try expect_equal(reason.kind, "ETIMEDOUT")

test "wait_all keeps order and wait_first returns the first result":
    let all = wait_all([promise(fn: ok(1)), promise(fn: ok(2)), promise(fn: ok(3))])
    all | try expect_ok | try expect_equal([1, 2, 3])

    let first = wait_first([promise(fn: ok(forever())), promise(fn: ok(4))])
    first | try expect_ok | try expect_equal(4)

test "a second wait reports that the result was taken":
    let work = promise(fn: ok(5))
    work.wait() | try expect_ok | try expect_equal(5)

    let again = work.wait() | try expect_error
    try expect_equal(again.kind, "EBADF")

test "a negative timeout waits no time instead of waiting forever":
    let slow = promise(
        fn: ok(forever()), options: PromiseOptions(timeout: nanoseconds(-1))
    )
    let reason = slow.wait() | try expect_error
    try expect_equal(reason.kind, "ETIMEDOUT")

test "a timeout counts from construction, so a late wait still reports Timeout":
    let slow = promise(
        fn: ok(forever()), options: PromiseOptions(timeout: milliseconds(20))
    )
    let _ = sleep(milliseconds(80)).wait()
    try expect_true(slow.done())

    let reason = slow.wait() | try expect_error
    try expect_equal(reason.kind, "ETIMEDOUT")

test "a promise from another call takes its limit with with":
    let quiet = sleep(milliseconds(5000)).with(
        options: PromiseOptions(timeout: milliseconds(20))
    )
    let reason = quiet.wait() | try expect_error
    try expect_equal(reason.kind, "ETIMEDOUT")

test "a result that arrives before the limit is kept":
    let quick = promise(fn: ok(9), options: PromiseOptions(timeout: milliseconds(5000)))
    quick.wait() | try expect_ok | try expect_equal(9)

test "cancel ends unfinished work and wait reports Cancelled":
    let slow = promise(fn: ok(forever()))
    slow.cancel()

    let reason = slow.wait() | try expect_error
    try expect_equal(reason.kind, "EUNKNOWN")
    try expect_equal(reason.message, "promise: cancelled")

test "one Cancel switch cancels every promise made with its signal":
    let stop = cancel_switch()
    let options = PromiseOptions(cancel: stop.signal())
    let a = promise(fn: ok(forever()), options: options.clone())
    let b = promise(fn: ok(forever()), options: options.clone())
    let slept = sleep(milliseconds(5000)).with(options: options.clone())
    stop.cancel()

    for p in [a, b]:
        let reason = p.wait() | try expect_error
        try expect_equal(reason.message, "promise: cancelled")

    let reason = slept.wait() | try expect_error
    try expect_equal(reason.message, "promise: cancelled")

test "a promise made with a signal that already fired is cancelled at once":
    let stop = cancel_switch()
    stop.cancel()

    let late = promise(
        fn: ok(forever()), options: PromiseOptions(cancel: stop.signal())
    )
    let reason = late.wait() | try expect_error
    try expect_equal(reason.message, "promise: cancelled")

test "a signal reports whether its switch fired, and a finished promise keeps its result":
    let stop = cancel_switch()
    let signal = stop.signal()
    let done = promise(fn: ok(3), options: PromiseOptions(cancel: stop.signal()))
    done.wait() | try expect_ok | try expect_equal(3)
    try expect_equal(signal.cancelled(), false)
    stop.cancel()
    try expect_equal(signal.cancelled(), true)

test "dropping the switch cancels nothing":
    let slow = promise(
        fn: ok(4), options: PromiseOptions(cancel: cancel_switch().signal())
    )
    slow.wait() | try expect_ok | try expect_equal(4)
