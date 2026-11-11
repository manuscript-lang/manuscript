import (
	join_errors, wrap_error from "@std/core.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
	deadline_after, monotonic, nanoseconds, sleep, ticker from "@std/time.ms",
)

test "wrap_error adds context and keeps the kind":
	gone := Error("gone", kind: "ENOENT", details: {"path": "a.txt"})
	outer := wrap_error("load", wrap_error("read", gone))
	try expect_equal(outer.message, "load: read: gone")
	try expect_equal(outer.kind, "ENOENT")
	try expect_equal(outer.details["path"], "a.txt")
	try expect_equal(outer.details["cause"], "read: gone")

test "join_errors reports each error and none for empty":
	none_joined := join_errors([])
	try expect_true(none_joined.is_none())

	both := join_errors([Error("a"), Error("b")])

	if joined := both:
		try expect_equal(joined.message, "a\nb")
		try expect_equal(joined.details["count"], "2")

test "deadline expires and ticker paces":
	d := deadline_after(20.milliseconds())
	try expect_false(d.expired())
	d.wait()
	try expect_true(d.expired())
	try expect_equal(d.remaining().to_nanoseconds(), 0)

	start := monotonic()
	var count = 0
	var ticks = ticker(10.milliseconds())

	while count < 3:
		tick := try ticks.next()
		try expect_true(tick.is_some())
		count += 1

	try expect_true(monotonic().difference(start).to_milliseconds() >= 29)

test "ticker keeps its original cadence when the consumer misses ticks":
	// Alignment is exact even on a loaded runner; no upper bound on elapsed time is
	// assumed.
	period := nanoseconds(10000019)
	var ticks = ticker(period.clone())
	first := (try ticks.next()).get().clone()

	for pause in [
		period.multiply(4).add(nanoseconds(1)),
		period.multiply(7).add(nanoseconds(3)),
	]:
		try sleep(pause).wait()

		pending := (try ticks.next()).get().clone()
		next := (try ticks.next()).get().clone()
		pending_offset := pending.difference(first).to_nanoseconds()
		next_offset := next.difference(first).to_nanoseconds()
		try expect_equal(pending_offset % period.to_nanoseconds(), 0)
		try expect_equal(next_offset % period.to_nanoseconds(), 0)
		try expect_true(next.difference(pending).compare(period) > 0)
