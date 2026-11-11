import (
	Promise, PromiseOptions, promise from "@std/concurrency/promise.ms",
	Pipe, ReadStream, WriteStream, pipe from "@std/io/io.ms",
	expect_equal, expect_error, expect_false, expect_true from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

fn drain(var input: ReadStream[Int]) List[Int]!:
	var seen: List[Int] = []
	for item in input:
		seen.append(item)
	return ok(seen)

test "a pipe delivers values in order and ends when every writer is closed":
	var p = pipe[Int](4)
	var out = p.writer()
	var input = p.reader()
	out.write(1)?
	out.write(2)?
	out.write(3)?
	out.close()?
	p.close()?
	expect_equal(drain(var input)?, [1, 2, 3])?

test "each writer is its own end like dup: the reader ends after the last one closes":
	var p = pipe[String](4)
	var first = p.writer()
	var second = p.writer()
	var input = p.reader()
	p.close()?
	first.write("a")?
	second.write("b")?
	first.close()?
	second.write("c")?
	second.close()?

	var seen: List[String] = []
	for item in input:
		seen.append(item)
	expect_equal(seen, ["a", "b", "c"])?

fn fill(p: Pipe[Int], count: Int) Unit!:
	var out = p.writer()
	for i in 0..count:
		out.write(i)?
	out.flush()?
	return out.close()

test "a write waits while the pipe holds more than its capacity, so the reader sets the pace":
	var p = pipe[Int](1)
	var input = p.reader()
	var gate = p.writer()
	producer := promise(fn: fill(p, 20))

	// The producer cannot finish 20 writes into a pipe of capacity 1 until the reader
	// takes values.
	sleep(milliseconds(50)).wait()?
	expect_false(producer.done())?

	var seen: List[Int] = []
	for i in 0..20:
		seen.append((input.next()?).get(-1))
	producer.wait()?
	gate.close()?
	expect_equal(
		seen,
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
	)?

test "a write fails with Closed once the reader is gone":
	var p = pipe[Int](2)
	var out = p.writer()
	var input = p.reader()
	input.close()?

	refused := expect_error(out.write(1))?
	expect_equal(refused.kind, "EBADF")?

test "a pipe has one reader; asking again gives a stream that has already ended":
	var p = pipe[Int](2)
	var out = p.writer()
	var input = p.reader()
	var again = p.reader()
	out.write(7)?
	expect_equal((again.next()?), none)?
	expect_equal((input.next()?), 7)?

test "a promise that owns a pipe writes to it through a writer of its own":
	var p = pipe[Int](8)
	var input = p.reader()

	// Holds the pipe open until the producer is done, since the reader ends when the
	// last writer closes.
	var gate = p.writer()
	producer := promise(fn: produce(p, 5))
	producer.wait()?
	gate.close()?
	expect_equal(drain(var input)?, [0, 1, 2, 3, 4])?

fn produce(p: Pipe[Int], count: Int) Unit!:
	var out = p.writer()
	for i in 0..count:
		out.write(i)?
	return out.close()

fn send_range(var out: WriteStream[Int], base: Int) Unit!:
	for i in 0..5:
		out.write(base + i)?
	return out.close()

test "several promises each move a writer of their own into a fan-in":
	var p = pipe[Int](2)
	var first = p.writer()
	var second = p.writer()
	var third = p.writer()
	var input = p.reader()
	a := promise(fn: ok(send_range(var first, 0)?))
	b := promise(fn: ok(send_range(var second, 100)?))
	c := promise(fn: ok(send_range(var third, 200)?))
	var seen = drain(var input)?
	seen.sort()
	a.wait()?
	b.wait()?
	c.wait()?
	expect_equal(seen.length(), 15)?
	expect_equal(seen[0], 0)?
	expect_equal(seen[14], 204)?

fn start_sender(p: Pipe[Int]) Promise[Unit]:
	var w = p.writer()
	return promise(fn: send_range(var w, 0))

// The promise owns the writer from the capture on: the function that made it returning
// does not close it.
test "a promise keeps the writer it captured after its maker returns":
	var p = pipe[Int](2)
	var input = p.reader()
	var gate = p.writer()
	sender := start_sender(p)
	gate.close()?
	expect_equal(drain(var input)?, [0, 1, 2, 3, 4])?
	sender.wait()?

fn send_many(var out: WriteStream[Int], from: Int, count: Int) Unit!:
	for i in from..from + count:
		out.write(i)?
	out.flush()?
	return out.close()

test "a reader takes queued values directly and still waits and ends in order":
	var p = pipe[Int](8)
	var first = p.writer()
	var second = p.writer()
	var input = p.reader()
	p.close()?

	a := promise(fn: send_many(var first, 0, 5000))
	b := promise(fn: send_many(var second, 5000, 5000))
	var total = 0
	var count = 0

	for v in input:
		total += v
		count += 1

	a.wait()?
	b.wait()?
	expect_equal(count, 10000)?
	expect_equal(total, 49995000)?

fn endless(var out: WriteStream[Int]) Unit!:
	var i = 0

	while true:
		out.write(i)?
		i += 1

fn sum_mod(var input: ReadStream[Int]) Int!:
	var n = 0
	for v in input:
		n += v % 3
	return ok(n)

test "a consumer that always finds a value queued still meets its timeout":
	var p = pipe[Int](1000000)
	var w = p.writer()
	var r = p.reader()
	p.close()?

	_prod := promise(fn: endless(var w))
	cons := promise(fn: sum_mod(var r)).with(
		options: PromiseOptions(timeout: milliseconds(200))
	)
	expect_true(cons.wait().is_error())?
