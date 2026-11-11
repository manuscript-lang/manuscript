import (
	ReadStream, Source, pipe from "@std/io/io.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	milliseconds, monotonic, sleep from "@std/time.ms",
)

// Forwards one read of `input`, itself bounded by `limit`.
type Forward:
	input: ReadStream[Int]
	limit: Int

impl Source[Int] for Forward:
	var fn next() Int?!:
		return self.input.next(timeout: milliseconds(self.limit))

	var fn close() Unit!:
		return self.input.close()

// Reads one value that is ready, then waits for a second that never comes.
type ReadyThenStall:
	input: ReadStream[Int]
	reads: Int = 0

impl Source[Int] for ReadyThenStall:
	var fn next() Int?!:
		self.reads += 1
		return self.input.next(timeout: milliseconds(600))

	var fn close() Unit!:
		return self.input.close()

test "an outer deadline bounds a longer nested read":
	var queue = pipe[Int](4)
	gate := queue.writer()
	var input = ReadStream[Int](Forward(queue.reader(), 600))
	started := monotonic()
	result := input.next(timeout: milliseconds(20))
	elapsed := monotonic().difference(started)
	try expect_equal(result.err().kind, "ETIMEDOUT")
	try expect_true(elapsed.compare(milliseconds(300)) < 0)

	_gate := gate

test "a shorter nested bound still applies inside a longer outer one":
	var queue = pipe[Int](4)
	gate := queue.writer()
	var input = ReadStream[Int](Forward(queue.reader(), 20))
	started := monotonic()
	result := input.next(timeout: milliseconds(600))
	elapsed := monotonic().difference(started)
	try expect_equal(result.err().kind, "ETIMEDOUT")
	try expect_true(elapsed.compare(milliseconds(300)) < 0)

	_gate := gate

test "a nested read that finishes at once leaves the outer deadline in force":
	var queue = pipe[Int](4)
	var gate = queue.writer()
	try gate.write(7)

	var input = ReadStream[Int](ReadyThenStall(queue.reader()))
	first := try input.next(timeout: milliseconds(600))
	expected: Int? := 7
	try expect_equal(first, expected)

	started := monotonic()
	second := input.next(timeout: milliseconds(20))
	elapsed := monotonic().difference(started)
	try expect_equal(second.err().kind, "ETIMEDOUT")
	try expect_true(elapsed.compare(milliseconds(300)) < 0)

test "a bound does not leak into a later unbounded wait":
	var queue = pipe[Int](4)
	var gate = queue.writer()
	var input = queue.reader()
	_early := input.next(timeout: milliseconds(10))
	sleep(milliseconds(50))
	try gate.write(5)

	value := try input.next()
	expected: Int? := 5
	try expect_equal(value, expected)
