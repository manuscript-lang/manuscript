import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	ReadStream, pipe from "@std/io/io.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

// Sums a stream that never delivers: the loop waits inside the source.
fn sum(input: ReadStream[Int]) Int!:
	var source = input
	var total = 0
	for n in source:
		total += n
	return ok(total)

test "a time limit on the loop cancels a source that waits forever":
	var p = pipe[Int](4)
	gate := p.writer()
	work := promise(fn: sum(p.reader())).with(
		options: PromiseOptions(timeout: milliseconds(100))
	)
	result := work.wait()
	expect_true(result.is_error())?

	_gate := gate

test "a cancel switch ends a loop that waits for an item":
	var p = pipe[Int](4)
	gate := p.writer()
	switch := cancel_switch()
	work := promise(fn: sum(p.reader())).with(
		options: PromiseOptions(cancel: switch.signal())
	)
	sleep(milliseconds(50)).wait()?
	switch.cancel()
	expect_true(work.wait().is_error())?

	_gate := gate
