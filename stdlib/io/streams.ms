import Bytes, BytesBuilder from "@std/bytes.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import Duration from "@std/os/time.ms"
import (ReadStream, WriteStream, Source) from "@std/io/io.ms"

// Steps for streams. Each takes its input first, so a pipeline is the `|` operator. A step pulls its input only
// inside its own `next`, so a slow consumer slows every step and the source, and closing a step closes its input.

// Lines of bytes, without their `\n` or `\r\n`, cut only at line ends; the unterminated last line comes at the end.
// `data` is the bytes held so far and `start` the first one not yet returned.
type Lines:
    input: ReadStream[Bytes]
    max_bytes: Int?
    data: Bytes
    start: Int
    ended: Bool

impl Lines:
    // Fails with `EOVERFLOW` when a line of `size` bytes is longer than the limit.
    fn check(size: Int) Unit!:
        if let limit = self.max_bytes:
            if size > limit:
                return error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))
        return ok(unit)

    // Decodes one line, or fails with `EBADMSG` rather than turning bytes that are not UTF-8 into an empty line.
    fn decode(line: Bytes) String!:
        if let text = line.decode_utf8():
            return ok(text)

        return error(Error("I/O: line is not valid UTF-8", kind: "EBADMSG"))

impl Source[String] for Lines:
    var fn next() String?!:
        while true:
            let end = self.data.index_of_byte(10, self.start)

            if end.is_some():
                let found = end.get()
                var stop = found
                if stop > self.start and self.data.get(stop - 1, 0) == 13:
                    stop -= 1
                try self.check(stop - self.start)

                let line = try self.data.slice(self.start, stop)
                self.start = found + 1
                return ok(try self.decode(line))

            if self.ended:
                if self.start < self.data.length():
                    let held = try self.data.slice(self.start, self.data.length())
                    try self.check(held.length())
                    self.start = self.data.length()
                    return ok(try self.decode(held))

                return ok(none)

            // A final `\r` may be the first half of a `\r\n` split across chunks, so it does not count toward the limit yet.
            var pending = self.data.length() - self.start
            if pending > 0 and self.data.get(self.data.length() - 1, 0) == 13:
                pending -= 1
            try self.check(pending)

            let chunk = try self.input.next()

            if let more = chunk:
                let held = try self.data.slice(self.start, self.data.length())
                self.data = held.concat(more)
                self.start = 0
            else:
                self.ended = true

        return ok(none)

    var fn close() Unit!:
        return self.input.close()

// Reads lines of text from a byte stream such as `stdin()`: splits `input` at `\n`, removing a trailing `\r`; a line longer than `max_bytes` is an error.
export fn lines(input: ReadStream[Bytes], max_bytes: Int? = none) ReadStream[String]:
    return ReadStream[String](Lines(input, max_bytes, "".to_bytes(), 0, false))

// Items of a list, in order. The list is the stream's own, held last item first so `pop` moves the next one out.
type ListSource[T]:
    items: List[T]

impl Source[T] for ListSource[T]:
    var fn next() T?!:
        return ok(self.items.pop())

    var fn close() Unit!:
        return ok(unit)

// A stream that yields the items of `items` in order and then ends.
export fn from_list[T](items: List[T]) ReadStream[T]:
    var reversed = items.clone()
    reversed.reverse()
    return ReadStream[T](ListSource[T](reversed))

// Chunks of at most `chunk_bytes` bytes of `data`.
type BytesSource:
    data: Bytes
    at: Int
    chunk: Int

impl Source[Bytes] for BytesSource:
    var fn next() Bytes?!:
        if self.chunk < 1:
            return error(Error("I/O: chunk size must be positive", kind: "EINVAL"))
        if self.at >= self.data.length():
            return ok(none)

        var stop = self.at + self.chunk
        if stop > self.data.length():
            stop = self.data.length()

        let piece = try self.data.slice(self.at, stop)
        self.at = stop
        return ok(piece)

    var fn close() Unit!:
        return ok(unit)

// A stream that yields `data` in chunks of at most `chunk_bytes` bytes and then ends. A `chunk_bytes` below 1 makes the first read fail with `EINVAL`.
export fn from_bytes(data: Bytes, chunk_bytes: Int = 65536) ReadStream[Bytes]:
    return ReadStream[Bytes](BytesSource(data, 0, chunk_bytes))

type Mapped[T, U]:
    input: ReadStream[T]
    f: fn(T) U

impl Source[U] for Mapped[T, U]:
    var fn next() U?!:
        let item = try self.input.next()
        if let value = item:
            return ok(self.f(value))

        return ok(none)

    var fn close() Unit!:
        return self.input.close()

// A stream of `f` applied to each item of `input`; closing it closes `input`.
export fn map[T, U](input: ReadStream[T], f: fn(T) U) ReadStream[U]:
    return ReadStream[U](Mapped[T, U](input, f))

type Filtered[T]:
    input: ReadStream[T]
    keep: fn(T) Bool

impl Source[T] for Filtered[T]:
    var fn next() T?!:
        while true:
            let item = try self.input.next()

            if let value = item:
                if self.keep(value):
                    return ok(value)
            else:
                return ok(none)

        return ok(none)

    var fn close() Unit!:
        return self.input.close()

// A stream of the items of `input` for which `keep` is true, in order; closing it closes `input`.
export fn filter[T](input: ReadStream[T], keep: fn(T) Bool) ReadStream[T]:
    return ReadStream[T](Filtered[T](input, keep))

// The first `left` items of another stream; it never pulls past them.
type Taker[T]:
    input: ReadStream[T]
    left: Int

impl Source[T] for Taker[T]:
    var fn next() T?!:
        if self.left <= 0:
            return ok(none)

        self.left -= 1
        return self.input.next()

    var fn close() Unit!:
        return self.input.close()

// A stream of at most the first `count` items of `input`, then the end: later items are never read, so `take` can
// end an endless stream. A `count` of 0 or less is an empty stream. Closing it closes `input`.
export fn take[T](input: ReadStream[T], count: Int) ReadStream[T]:
    return ReadStream[T](Taker[T](input, count))

// One read of the stream in `held[0]`, in a task that `limit` can cancel. The task works on the list in place and is
// over when this returns.
fn read_within[T](var held: List[ReadStream[T]], limit: Duration) T?!:
    return promise(fn: held[0].next()).with(
        options: PromiseOptions(timeout: limit)
    ).wait()

// Each wait for an item gets at most `limit`. The stream sits in a list so a read can use it in place. A read that
// fails, a timeout included, closes the stream; later reads end.
type Timed[T]:
    held: List[ReadStream[T]]
    limit: Duration

impl Source[T] for Timed[T]:
    var fn next() T?!:
        if self.held.length() == 0:
            return ok(none)

        let item = read_within(var self.held, self.limit.clone())
        if item.is_error():
            let _ = self.held.pop()
        return item

    var fn close() Unit!:
        if let input = self.held.pop():
            var closing = input
            return closing.close()

        return ok(unit)

// `input` with a time limit on every item: a wait longer than `limit` fails with `ETIMEDOUT` and cancels the read.
// Limit a whole pipeline by running its loop in a promise with `PromiseOptions(timeout: ...)`.
export fn timeout[T](input: ReadStream[T], limit: Duration) ReadStream[T]:
    return ReadStream[T](Timed[T]([input], limit))

// Combines the items of `input` in order into one value: `f` takes the value so far and the next item, starting from `start`.
export fn fold[T, S](input: ReadStream[T], start: S, f: fn(S, T) S) S!:
    var source = input
    var total = start
    for item in source:
        total = f(total, item)
    return ok(total)

// Every item of `input`, in order; more than `max_items` items is an error.
export fn collect[T](input: ReadStream[T], max_items: Int?) List[T]!:
    var source = input
    var items: List[T] = []

    for item in source:
        items.append(item)
        if let limit = max_items:
            if items.length() > limit:
                return error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))

    return ok(items)

// All bytes of `input`; more than `max_bytes` bytes is an error.
export fn read_all(input: ReadStream[Bytes], max_bytes: Int?) Bytes!:
    var source = input
    var all = BytesBuilder()
    var total = 0

    for chunk in source:
        all.append_bytes(chunk)
        total += chunk.length()
        if let limit = max_bytes:
            if total > limit:
                return error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))

    return ok(all.build())

// Moves every item of `input` to `output`, pulling the next only after `write` accepts the last; answers how many.
export fn copy[T](input: ReadStream[T], output: WriteStream[T]) Int!:
    var source = input
    var sink = output
    var count = 0

    for item in source:
        try sink.write(item)
        count += 1

    try sink.flush()
    return ok(count)
