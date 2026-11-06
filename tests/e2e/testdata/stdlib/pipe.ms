import expect_equal, expect_false, expect_true, expect_error from "@std/test/test.ms"
import Pipe, pipe, ReadStream, WriteStream from "@std/io/io.ms"
import Promise, promise from "@std/concurrency/promise.ms"
import sleep, milliseconds from "@std/time.ms"

fn drain(var input: ReadStream[Int]) List[Int]!:
    var seen: List[Int] = []
    for item in input:
        seen.append(item)
    return ok(seen)

test "a pipe delivers values in order and ends when every writer is closed":
    var p = pipe[Int](4)
    var out = p.writer()
    var input = p.reader()
    try out.write(1)
    try out.write(2)
    try out.write(3)
    try out.close()
    try p.close()
    try expect_equal(try drain(var input), [1, 2, 3])

test "each writer is its own end like dup: the reader ends after the last one closes":
    var p = pipe[String](4)
    var first = p.writer()
    var second = p.writer()
    var input = p.reader()
    try p.close()
    try first.write("a")
    try second.write("b")
    try first.close()
    try second.write("c")
    try second.close()

    var seen: List[String] = []
    for item in input:
        seen.append(item)
    try expect_equal(seen, ["a", "b", "c"])

fn fill(p: Pipe[Int], count: Int) Unit!:
    var out = p.writer()
    for i in 0..count:
        try out.write(i)
    try out.flush()
    return out.close()

test "a write waits while the pipe holds more than its capacity, so the reader sets the pace":
    var p = pipe[Int](1)
    var input = p.reader()
    var gate = p.writer()
    let producer = promise(fn: fill(p, 20))

    // The producer cannot finish 20 writes into a pipe of capacity 1 until the reader takes values.
    try sleep(milliseconds(50)).wait()
    try expect_false(producer.done())

    var seen: List[Int] = []
    for i in 0..20:
        seen.append((try input.next()).get(-1))
    try producer.wait()
    try gate.close()
    try expect_equal(
        seen, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
    )

test "a write fails with Closed once the reader is gone":
    var p = pipe[Int](2)
    var out = p.writer()
    var input = p.reader()
    try input.close()

    let refused = try expect_error(out.write(1))
    try expect_equal(refused.kind, "EBADF")

test "a pipe has one reader; asking again gives a stream that has already ended":
    var p = pipe[Int](2)
    var out = p.writer()
    var input = p.reader()
    var again = p.reader()
    try out.write(7)
    try expect_equal((try again.next()), none)
    try expect_equal((try input.next()), 7)

test "a promise that owns a pipe writes to it through a writer of its own":
    var p = pipe[Int](8)
    var input = p.reader()

    // Holds the pipe open until the producer is done, since the reader ends when the last writer closes.
    var gate = p.writer()
    let producer = promise(fn: produce(p, 5))
    try producer.wait()
    try gate.close()
    try expect_equal(try drain(var input), [0, 1, 2, 3, 4])

fn produce(p: Pipe[Int], count: Int) Unit!:
    var out = p.writer()
    for i in 0..count:
        try out.write(i)
    return out.close()

fn send_range(var out: WriteStream[Int], base: Int) Unit!:
    for i in 0..5:
        try out.write(base + i)
    return out.close()

test "several promises each move a writer of their own into a fan-in":
    var p = pipe[Int](2)
    var first = p.writer()
    var second = p.writer()
    var third = p.writer()
    var input = p.reader()
    let a = promise(fn: ok(try send_range(var first, 0)))
    let b = promise(fn: ok(try send_range(var second, 100)))
    let c = promise(fn: ok(try send_range(var third, 200)))
    var seen = try drain(var input)
    seen.sort()
    try a.wait()
    try b.wait()
    try c.wait()
    try expect_equal(seen.length(), 15)
    try expect_equal(seen[0], 0)
    try expect_equal(seen[14], 204)

fn start_sender(p: Pipe[Int]) Promise[Unit]:
    var w = p.writer()
    return promise(fn: send_range(var w, 0))

// The promise owns the writer from the capture on: the function that made it returning does not close it.
test "a promise keeps the writer it captured after its maker returns":
    var p = pipe[Int](2)
    var input = p.reader()
    var gate = p.writer()
    let sender = start_sender(p)
    try gate.close()
    try expect_equal(try drain(var input), [0, 1, 2, 3, 4])
    try sender.wait()
