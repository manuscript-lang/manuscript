import expect_equal, expect_true, expect_false from "@std/test/test.ms"
import TextError, ContextError, wrap, join from "@std/core.ms"
import share from "@std/concurrency/shared.ms"
import once, lock from "@std/concurrency/sync.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import sleep, deadline_after, ticker, monotonic from "@std/os/time.ms"

test "once runs the action a single time across tasks":
    let gate = once()
    let hits = share(0)
    var group = TaskGroup[Unit]()

    for i in 0..3:
        let mine = gate.clone()
        let count = hits
        group.spawn(
            fn(ch):
                mine.run(
                    fn():
                        sleep(5.milliseconds)

                        var guard = lock(count)
                        guard.value += 1
                )
            ,
            none
        )

    try group.wait()
    try expect_equal(hits.get(), 1)
    try expect_true(gate.is_done())

test "wrap adds context and keeps the cause":
    let outer = wrap("load", wrap("read", TextError("gone")))
    try expect_equal(outer.message(), "load: read: gone")

    match outer.cause:
        ContextError(inner): try expect_equal(inner.context, "read")
        _: try expect_true(false)

test "join reports each error and none for empty":
    let none_joined = join([])
    try expect_true(none_joined.is_none())

    let both = join([TextError("a"), TextError("b")])
    if let joined = both:
        try expect_equal(joined.message(), "a\nb")

test "deadline expires and ticker paces":
    let d = deadline_after(20.milliseconds)
    try expect_false(d.expired())
    d.wait()
    try expect_true(d.expired())
    try expect_equal(d.remaining().to_nanoseconds(), 0)

    let start = monotonic()
    var count = 0

    for tick in ticker(10.milliseconds):
        count += 1
        if count == 3: break

    try expect_true(monotonic().difference(start).to_milliseconds() >= 29)
