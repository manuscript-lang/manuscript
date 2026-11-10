import (
	panic from "@std/core.ms",
	Promise,
	promise,
	wait_all,
	wait_first,
	PromiseOptions,
	cancel_switch from "@std/concurrency/promise.ms",
	expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms",
	milliseconds, nanoseconds, sleep from "@std/time.ms",
)

fn report(reason: Error) String:
	if reason.kind == "EIO": return reason.details["report"].split("\n").get(0).clone()

	return reason.message.clone()

fn forever() Int:
	for i in 0..600:
		_ := sleep(milliseconds(100)).wait()
	return 0

test "a fault inside a promise ends only that promise":
	broken := promise(fn: ok(panic("promise fault")))
	fine := promise(fn: ok(7))
	reason := broken.wait() | try expect_error
	report(reason) | try expect_equal("promise fault")
	fine.wait() | try expect_ok | try expect_equal(7)

fn fault_at(index: Int) Int!:
	empty: List[Int] = []
	return ok(empty[index])

// Faults on different scheduler threads leave their guards at the same moment. They once shared one message
// cell, so a report came back empty or from another promise, and a string was released twice.
test "promises faulting on several threads each report their own fault":
	for round in 0..100:
		var batch: List[Promise[Int]] = []
		for i in 0..200:
			batch.append(promise(fn: fault_at(round * 1000 + i + 1)))

		for i in 0..batch.length():
			reason := batch[i].wait() | try expect_error
			text := report(reason)
			try expect_true(text.contains("index {round * 1000 + i + 1} out of range"))

test "a timed out wait reports Timeout and cancels the work":
	slow := promise(
		fn: ok(forever()), options: PromiseOptions(timeout: milliseconds(20))
	)
	reason := slow.wait() | try expect_error
	try expect_equal(reason.kind, "ETIMEDOUT")

test "wait_all keeps order and wait_first returns the first result":
	all := wait_all([promise(fn: ok(1)), promise(fn: ok(2)), promise(fn: ok(3))])
	all | try expect_ok | try expect_equal([1, 2, 3])

	first := wait_first([promise(fn: ok(forever())), promise(fn: ok(4))])
	first | try expect_ok | try expect_equal(4)

test "wait_all ends at the first failure in time, not list order":
	results := wait_all(
		[
			promise(fn: ok(forever())),
			promise[Int](fn: error(Error("boom", kind: "EFAIL")))
		]
	)
	reason := results | try expect_error
	try expect_equal(reason.kind, "EFAIL")

test "wait_all keeps order when later promises finish first":
	slow := promise(
		fn:
			_ := sleep(milliseconds(30)).wait()
			return ok(1)
	)

	wait_all([slow, promise(fn: ok(2)), promise(fn: ok(3))])
		| try expect_ok
		| try expect_equal([1, 2, 3])

test "a second wait reports that the result was taken":
	work := promise(fn: ok(5))
	work.wait() | try expect_ok | try expect_equal(5)

	again := work.wait() | try expect_error
	try expect_equal(again.kind, "EBADF")

test "a negative timeout waits no time instead of waiting forever":
	slow := promise(
		fn: ok(forever()), options: PromiseOptions(timeout: nanoseconds(-1))
	)
	reason := slow.wait() | try expect_error
	try expect_equal(reason.kind, "ETIMEDOUT")

test "a timeout counts from construction, so a late wait still reports Timeout":
	slow := promise(
		fn: ok(forever()), options: PromiseOptions(timeout: milliseconds(20))
	)
	_ := sleep(milliseconds(80)).wait()
	try expect_true(slow.done())

	reason := slow.wait() | try expect_error
	try expect_equal(reason.kind, "ETIMEDOUT")

test "a promise from another call takes its limit with with":
	quiet := sleep(milliseconds(5000)).with(
		options: PromiseOptions(timeout: milliseconds(20))
	)
	reason := quiet.wait() | try expect_error
	try expect_equal(reason.kind, "ETIMEDOUT")

test "a result that arrives before the limit is kept":
	quick := promise(fn: ok(9), options: PromiseOptions(timeout: milliseconds(5000)))
	quick.wait() | try expect_ok | try expect_equal(9)

test "cancel ends unfinished work and wait reports Cancelled":
	slow := promise(fn: ok(forever()))
	slow.cancel()

	reason := slow.wait() | try expect_error
	try expect_equal(reason.kind, "ECANCELED")
	try expect_equal(reason.message, "promise: cancelled")

test "one Cancel switch cancels every promise made with its signal":
	stop := cancel_switch()
	options := PromiseOptions(cancel: stop.signal())
	a := promise(fn: ok(forever()), options: options.clone())
	b := promise(fn: ok(forever()), options: options.clone())
	slept := sleep(milliseconds(5000)).with(options: options.clone())
	stop.cancel()

	for p in [a, b]:
		reason := p.wait() | try expect_error
		try expect_equal(reason.message, "promise: cancelled")

	reason := slept.wait() | try expect_error
	try expect_equal(reason.message, "promise: cancelled")

test "a promise made with a signal that already fired is cancelled at once":
	stop := cancel_switch()
	stop.cancel()

	late := promise(fn: ok(forever()), options: PromiseOptions(cancel: stop.signal()))
	reason := late.wait() | try expect_error
	try expect_equal(reason.message, "promise: cancelled")

test "a signal reports whether its switch fired, and a finished promise keeps its result":
	stop := cancel_switch()
	signal := stop.signal()
	done := promise(fn: ok(3), options: PromiseOptions(cancel: stop.signal()))
	done.wait() | try expect_ok | try expect_equal(3)
	try expect_equal(signal.cancelled(), false)
	stop.cancel()
	try expect_equal(signal.cancelled(), true)

test "dropping the switch cancels nothing":
	slow := promise(
		fn: ok(4), options: PromiseOptions(cancel: cancel_switch().signal())
	)
	slow.wait() | try expect_ok | try expect_equal(4)

test "a replacement cancel signal detaches the previous switch":
	first := cancel_switch()
	second := cancel_switch()
	slow := sleep(milliseconds(5000)).with(
		options: PromiseOptions(cancel: first.signal())
	).with(options: PromiseOptions(cancel: second.signal()))
	first.cancel()
	try expect_equal(slow.done(), false)
	second.cancel()

	reason := slow.wait() | try expect_error
	try expect_equal(reason.kind, "ECANCELED")

fn ignore_inner(inner: Promise[Int]) Int!:
	return ok(1)

fn nap(ms: Int) Int!:
	sleep(milliseconds(ms)).wait().get(unit)
	return ok(ms)

test "a promise that ends holding an unfinished promise cancels it instead of hanging":
	for round in 0..20:
		inner := promise(fn: nap(100000))
		outer := promise(fn: ignore_inner(inner))
		try expect_equal(outer.wait() | try expect_ok, 1)
