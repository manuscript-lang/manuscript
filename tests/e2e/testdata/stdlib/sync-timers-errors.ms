import expect_equal, expect_true, expect_false from "@std/test/test.ms"
import wrap_error, join_errors from "@std/core.ms"
import sleep, deadline_after, ticker, monotonic from "@std/os/time.ms"

test "wrap_error adds context and keeps the kind":
    let gone = Error("gone", kind: "ENOENT", details: {"path": "a.txt"})
    let outer = wrap_error("load", wrap_error("read", gone))
    try expect_equal(outer.message, "load: read: gone")
    try expect_equal(outer.kind, "ENOENT")
    try expect_equal(outer.details["path"], "a.txt")
    try expect_equal(outer.details["cause"], "read: gone")

test "join_errors reports each error and none for empty":
    let none_joined = join_errors([])
    try expect_true(none_joined.is_none())

    let both = join_errors([Error("a"), Error("b")])

    if let joined = both:
        try expect_equal(joined.message, "a\nb")
        try expect_equal(joined.details["count"], "2")

test "deadline expires and ticker paces":
    let d = deadline_after(20.milliseconds())
    try expect_false(d.expired())
    d.wait()
    try expect_true(d.expired())
    try expect_equal(d.remaining().to_nanoseconds(), 0)

    let start = monotonic()
    var count = 0
    var ticks = ticker(10.milliseconds())

    while count < 3:
        let tick = try ticks.read().wait()
        try expect_true(tick.is_some())
        count += 1

    try expect_true(monotonic().difference(start).to_milliseconds() >= 29)
