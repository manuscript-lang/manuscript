// conform: tags=testing,tier-io
// conform: phase=test
import (
	Promise,
	PromiseOptions,
	cancel_switch,
	promise,
	wait_all,
	wait_first from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
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
	reason := broken.wait() | expect_error?
	report(reason) | expect_equal("promise fault")?
	fine.wait() | expect_ok? | expect_equal(7)?

fn fault_at(index: Int) Int!:
	empty: List[Int] := []
	return ok(empty[index])

// Faults on different scheduler threads leave their guards at the same moment. They
// once shared one message cell, so a report came back empty or from another promise,
// and a string was released twice.
test "promises faulting on several threads each report their own fault":
	for round in 0..100:
		var batch: List[Promise[Int]] = []
		for i in 0..200:
			batch.append(promise(fn: fault_at(round * 1000 + i + 1)))

		for i in 0..batch.length():
			reason := batch[i].wait() | expect_error?
			text := report(reason)
			expect_true(text.contains("index {round * 1000 + i + 1} out of range"))?

test "a timed out wait reports Timeout and cancels the work":
	slow := promise(
		fn: ok(forever()),
		options: PromiseOptions(timeout: milliseconds(20))
	)
	reason := slow.wait() | expect_error?
	expect_equal(reason.kind, "ETIMEDOUT")?

test "wait_all keeps order and wait_first returns the first result":
	all := wait_all([promise(fn: ok(1)), promise(fn: ok(2)), promise(fn: ok(3))])
	all | expect_ok? | expect_equal([1, 2, 3])?

	first := wait_first([promise(fn: ok(forever())), promise(fn: ok(4))])
	first | expect_ok? | expect_equal(4)?

test "wait_all ends at the first failure in time, not list order":
	results := wait_all(
		[
			promise(fn: ok(forever())),
			promise[Int](fn: error(Error("boom", kind: "EFAIL"))),
		]
	)
	reason := results | expect_error?
	expect_equal(reason.kind, "EFAIL")?

test "wait_all keeps order when later promises finish first":
	slow := promise(
		fn:
			_ := sleep(milliseconds(30)).wait()
			return ok(1)
	)

	(
		wait_all(
			[slow, promise(fn: ok(2)), promise(fn: ok(3))]
		) | expect_ok? | expect_equal([1, 2, 3])?
	)

test "a second wait reports that the result was taken":
	work := promise(fn: ok(5))
	work.wait() | expect_ok? | expect_equal(5)?

	again := work.wait() | expect_error?
	expect_equal(again.kind, "EBADF")?

test "a negative timeout waits no time instead of waiting forever":
	slow := promise(
		fn: ok(forever()),
		options: PromiseOptions(timeout: nanoseconds(-1))
	)
	reason := slow.wait() | expect_error?
	expect_equal(reason.kind, "ETIMEDOUT")?

test "a timeout counts from construction, so a late wait still reports Timeout":
	slow := promise(
		fn: ok(forever()),
		options: PromiseOptions(timeout: milliseconds(20))
	)
	_ := sleep(milliseconds(80)).wait()
	expect_true(slow.done())?

	reason := slow.wait() | expect_error?
	expect_equal(reason.kind, "ETIMEDOUT")?

test "a promise from another call takes its limit with with":
	quiet := sleep(milliseconds(5000)).with(
		options: PromiseOptions(timeout: milliseconds(20))
	)
	reason := quiet.wait() | expect_error?
	expect_equal(reason.kind, "ETIMEDOUT")?

test "a result that arrives before the limit is kept":
	quick := promise(fn: ok(9), options: PromiseOptions(timeout: milliseconds(5000)))
	quick.wait() | expect_ok? | expect_equal(9)?

test "cancel ends unfinished work and wait reports Cancelled":
	slow := promise(fn: ok(forever()))
	slow.cancel()

	reason := slow.wait() | expect_error?
	expect_equal(reason.kind, "ECANCELED")?
	expect_equal(reason.message, "promise: cancelled")?

test "one Cancel switch cancels every promise made with its signal":
	stop := cancel_switch()
	options := PromiseOptions(cancel: stop.signal())
	a := promise(fn: ok(forever()), options: options.clone())
	b := promise(fn: ok(forever()), options: options.clone())
	slept := sleep(milliseconds(5000)).with(options: options.clone())
	stop.cancel()

	for p in [a, b]:
		reason := p.wait() | expect_error?
		expect_equal(reason.message, "promise: cancelled")?

	reason := slept.wait() | expect_error?
	expect_equal(reason.message, "promise: cancelled")?

test "a promise made with a signal that already fired is cancelled at once":
	stop := cancel_switch()
	stop.cancel()

	late := promise(fn: ok(forever()), options: PromiseOptions(cancel: stop.signal()))
	reason := late.wait() | expect_error?
	expect_equal(reason.message, "promise: cancelled")?

test "a signal reports whether its switch fired, and a finished promise keeps its result":
	stop := cancel_switch()
	signal := stop.signal()
	done := promise(fn: ok(3), options: PromiseOptions(cancel: stop.signal()))
	done.wait() | expect_ok? | expect_equal(3)?
	expect_equal(signal.cancelled(), false)?
	stop.cancel()
	expect_equal(signal.cancelled(), true)?

test "dropping the switch cancels nothing":
	slow := promise(
		fn: ok(4),
		options: PromiseOptions(cancel: cancel_switch().signal())
	)
	slow.wait() | expect_ok? | expect_equal(4)?

test "a replacement cancel signal detaches the previous switch":
	first := cancel_switch()
	second := cancel_switch()
	slow := sleep(milliseconds(5000)).with(
		options: PromiseOptions(cancel: first.signal())
	).with(options: PromiseOptions(cancel: second.signal()))
	first.cancel()
	expect_equal(slow.done(), false)?
	second.cancel()

	reason := slow.wait() | expect_error?
	expect_equal(reason.kind, "ECANCELED")?

fn ignore_inner(inner: Promise[Int]) Int!:
	return ok(1)

fn nap(ms: Int) Int!:
	sleep(milliseconds(ms)).wait().get(unit)
	return ok(ms)

test "a promise that ends holding an unfinished promise cancels it instead of hanging":
	for round in 0..20:
		inner := promise(fn: nap(100000))
		outer := promise(fn: ignore_inner(inner))
		expect_equal(outer.wait() | expect_ok?, 1)?

test "waiting in creation, reverse and interleaved order returns every promise's own value":
	var made: List[Promise[Int]] = []
	for i in 0..64:
		made.append(promise(fn: ok(i * 3)))

	// Oldest first, then newest first, then from the middle outward.
	for i in 0..16:
		(
			made[i].wait()
			| expect_ok?
			| expect_equal(i * 3)?
		)

	var j = 63

	while j >= 48:
		(
			made[j].wait()
			| expect_ok?
			| expect_equal(j * 3)?
		)
		j -= 1

	for i in 16..48:
		(
			made[i].wait()
			| expect_ok?
			| expect_equal(i * 3)?
		)
