import expect_equal, expect_true from "@std/test/test.ms"
import pipe, ReadStream from "@std/io/io.ms"
import timeout from "@std/io/streams.ms"
import promise, PromiseOptions, cancel_switch from "@std/concurrency/promise.ms"
import sleep, milliseconds from "@std/os/time.ms"

// Sums a stream that never delivers: the loop waits inside the source.
fn sum(input: ReadStream[Int]) Int!:
    var source = input
    var total = 0
    for n in source:
        total += n
    return ok(total)

test "a time limit on the loop cancels a source that waits forever":
    var p = pipe[Int](4)
    let gate = p.writer()
    let work = promise(fn: sum(p.reader())).with(
        options: PromiseOptions(timeout: milliseconds(100))
    )
    let result = work.wait()
    try expect_true(result.is_error())

    let _gate = gate

test "a cancel switch ends a loop that waits for an item":
    var p = pipe[Int](4)
    let gate = p.writer()
    let switch = cancel_switch()
    let work = promise(fn: sum(p.reader())).with(
        options: PromiseOptions(cancel: switch.signal())
    )
    try sleep(milliseconds(50)).wait()
    switch.cancel()
    try expect_true(work.wait().is_error())

    let _gate = gate

test "the timeout stage limits each wait for an item":
    var p = pipe[Int](4)
    var out = p.writer()
    try out.write(7)

    var timed = p.reader() | timeout(milliseconds(100))
    try expect_equal((try timed.next()), 7)
    try expect_true(timed.next().is_error())
    try expect_equal((try timed.next()), none)

    let _out = out
