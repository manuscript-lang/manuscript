import panic from "@std/core.ms"
import promise, wait_all, wait_first from "@std/concurrency/promise.ms"
import (expect_equal, expect_error, expect_ok) from "@std/test/test.ms"
import milliseconds, sleep from "@std/os/time.ms"

fn report(reason: Error) String:
    if reason.kind == ErrorCategory.Failed:
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
    let slow = promise(fn: ok(forever()))
    let reason = slow.wait(timeout: milliseconds(20)) | try expect_error
    try expect_equal(reason.kind, ErrorCategory.Timeout)

test "wait_all keeps order and wait_first returns the first result":
    let all = wait_all([promise(fn: ok(1)), promise(fn: ok(2)), promise(fn: ok(3))])
    all | try expect_ok | try expect_equal([1, 2, 3])

    let first = wait_first([promise(fn: ok(forever())), promise(fn: ok(4))])
    first | try expect_ok | try expect_equal(4)

test "a second wait reports that the result was taken":
    let work = promise(fn: ok(5))
    work.wait() | try expect_ok | try expect_equal(5)

    let again = work.wait() | try expect_error
    try expect_equal(again.kind, ErrorCategory.Closed)
