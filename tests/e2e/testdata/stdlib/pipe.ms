import expect_equal, expect_false, expect_true, expect_error from "@std/test/test.ms"
import Pipe, pipe, ReadStream from "@std/io/io.ms"
import promise from "@std/concurrency/promise.ms"

fn drain(var input: ReadStream[Int]) List[Int]!:
    var seen: List[Int] = []
    for item in input.wait():
        seen.append(try item)
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
    for item in input.wait():
        seen.append(try item)
    try expect_equal(seen, ["a", "b", "c"])

test "flush waits until the reader has taken the queue down to the capacity":
    var p = pipe[Int](1)
    var out = p.writer()
    var input = p.reader()
    try out.write(1)
    try out.write(2)
    try out.write(3)
    try expect_equal(out.buffered(), 3)

    let drained = out.flush()
    try expect_false(drained.done())

    let first = try input.read().wait()
    try expect_equal(first.get(0), 1)
    try expect_false(drained.done())

    let second = try input.read().wait()
    try expect_equal(second.get(0), 2)
    try drained.wait()
    try expect_equal(out.buffered(), 1)

test "a write fails with Closed once the reader is gone":
    var p = pipe[Int](2)
    var out = p.writer()
    var input = p.reader()
    try input.close()

    let refused = try expect_error(out.write(1))
    try expect_equal(refused.kind, ErrorCategory.Closed)

test "a pipe has one reader; asking again gives a stream that has already ended":
    var p = pipe[Int](2)
    var out = p.writer()
    var input = p.reader()
    var again = p.reader()
    try out.write(7)
    try expect_equal((try again.read().wait()), none)
    try expect_equal((try input.read().wait()), 7)

test "a promise that owns a pipe writes to it through a writer of its own":
    var p = pipe[Int](2)
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
