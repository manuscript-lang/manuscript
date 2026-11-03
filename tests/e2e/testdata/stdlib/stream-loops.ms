import expect_equal from "@std/test/test.ms"
import ReadStream, Source, WriteStream, stream, pipe from "@std/io/io.ms"
import from_list, map, collect, copy from "@std/io/streams.ms"

// Counts up to `stop`, fails once at `fail_at`, and reports where it was when closed.
type Counter:
    at: Int
    stop: Int
    fail_at: Int
    closes: WriteStream[Int]

impl Source[Int] for Counter:
    var fn next() Int?!:
        if self.at == self.fail_at:
            self.at += 1
            return error(Error("boom", kind: ErrorCategory.Failed))
        if self.at >= self.stop:
            return ok(none)
        self.at += 1
        return ok(self.at)

    var fn close() Unit!:
        try self.closes.write(self.at)
        return ok(unit)

test "a loop that breaks hands the source back to its stream":
    var closes = pipe[Int](capacity: 8)
    var s = stream[Int](Counter(0, 5, -1, closes.writer()))
    var seen: List[Int] = []
    for x in s.wait():
        seen.append(try x)
        if seen.length() == 2:
            break
    let next = try s.read().wait()
    try expect_equal(next.get(-1), 3)
    for x in s.wait():
        seen.append(try x)
    try expect_equal(seen, [1, 2, 4, 5])
    try s.close()
    try expect_equal(try closes.receive(), 5)

test "an error ends the loop and the stream reads on":
    var closes = pipe[Int](capacity: 8)
    var s = stream[Int](Counter(0, 3, 1, closes.writer()))
    var failures = 0
    for x in s.wait():
        if x.is_error():
            failures += 1
    try expect_equal(failures, 1)
    let next = try s.read().wait()
    try expect_equal(next.get(-1), 3)

test "closing the stream inside its loop still closes the source once":
    var closes = pipe[Int](capacity: 8)
    var s = stream[Int](Counter(0, 4, -1, closes.writer()))
    for x in s.wait():
        if (try x) == 2:
            try s.close()
    try expect_equal(try closes.receive(), 4)

test "stages pull directly and keep their results":
    let doubled = try collect(from_list([1, 2, 3]) | map(fn v: v * 2), none)
    try expect_equal(doubled, [2, 4, 6])
    let limited = collect(from_list([1, 2, 3]), 2)
    try expect_equal(limited.err().kind, ErrorCategory.LimitExceeded)

test "a stage over a stream with a pending read reads through it":
    var closes = pipe[Int](capacity: 8)
    var s = stream[Int](Counter(0, 3, -1, closes.writer()))
    let pending = s.read()
    let rest = try collect(s | map(fn v: v + 100), none)
    try expect_equal(rest, [101, 102, 103])
    try expect_equal(pending.wait().is_error(), true)

test "copy moves every item":
    var out = pipe[Int](capacity: 8)
    var writer = out.writer()
    let count = try copy(from_list([7, 8, 9]), writer)
    try expect_equal(count, 3)
