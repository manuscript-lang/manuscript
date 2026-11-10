import (
    Bytes, BytesBuilder, join from "@std/bytes.ms",
    ReadStream, WriteStream, Source from "@std/io/io.ms",
)

// Steps for streams. Each takes its input first, so a pipeline is the `|` operator. A step pulls its input only
// inside its own `next`, so a slow consumer slows every step and the source, and closing a step closes its input.

// Lines of bytes, without their `\n` or `\r\n`, cut only at line ends; the unterminated last line comes at the end.
// `data` is the current chunk and `start` the first unread byte; `pending` owns earlier unfinished fragments.
type Lines:
    input: ReadStream[Bytes]
    max_bytes: Int?
    data: Bytes
    start: Int
    ended: Bool
    pending: List[Bytes]
    pending_size: Int
    pending_cr: Bool

impl Lines:
    // Fails with `EOVERFLOW` when a line of `size` bytes is longer than the limit.
    fn check(size: Int) Unit!:
        if limit := self.max_bytes:
            if size > limit:
                return error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))

    // Decodes the held bytes in `[start, stop)` as one line, or fails with `EBADMSG` rather than turning bytes that are not UTF-8 into an empty line. The range is decoded in place, with no `Bytes` copy of the line first.
    fn decode(start: Int, stop: Int) String!:
        if text := self.data.decode_utf8_range(start, stop): return ok(text)

        return error(Error("I/O: line is not valid UTF-8", kind: "EBADMSG"))

impl Lines:
    // Joins only a completed line; incomplete chunks are copied once, not as a growing prefix.
    var fn take(stop: Int, terminated: Bool) String!:
        if self.pending_size == 0:
            var end = stop
            if terminated and end > self.start and self.data.get(end - 1, 0) == 13:
                end -= 1
            try self.check(end - self.start)

            from := self.start
            self.start = if terminated: stop + 1 else: stop
            return self.decode(from, end)

        size := self.pending_size + stop - self.start
        cr := if stop > self.start: self.data.get(stop - 1, 0) == 13 else: self.pending_cr
        trimmed := if terminated and cr: size - 1 else: size
        try self.check(trimmed)
        self.pending.append(try self.data.slice(self.start, stop))

        all := join(self.pending)
        self.pending = []
        self.pending_size = 0
        self.pending_cr = false
        self.start = if terminated: stop + 1 else: stop
        if text := all.decode_utf8_range(0, trimmed): return ok(text)

        return error(Error("I/O: line is not valid UTF-8", kind: "EBADMSG"))

impl Source[String] for Lines:
    var fn next() String?!:
        while true:
            if end := self.data.index_of_byte(10, self.start):
                if self.pending_size > 0: return ok(try self.take(end, true))

                var stop = end
                if stop > self.start and self.data.get(stop - 1, 0) == 13:
                    stop -= 1
                try self.check(stop - self.start)

                from := self.start
                self.start = end + 1
                return ok(try self.decode(from, stop))

            if self.ended:
                if self.pending_size > 0 or self.start < self.data.length():
                    return ok(try self.take(self.data.length(), false))

                return ok(none)

            // A trailing CR may belong to a split CRLF, so defer counting it until the next chunk or EOF.
            rest := self.data.length() - self.start
            cr := if rest > 0: self.data.get(self.data.length() - 1, 0) == 13 else: self.pending_cr
            try self.check(self.pending_size + rest - if cr: 1 else: 0)

            chunk := try self.input.next()

            if more := chunk:
                if rest > 0:
                    self.pending.append(
                        try self.data.slice(
                            self.start, self.data.length()
                        )
                    )
                    self.pending_size += rest
                    self.pending_cr = cr

                self.data = more
                self.start = 0
            else:
                self.ended = true

        return ok(none)

    var fn close() Unit!:
        return self.input.close()

// Reads lines of text from a byte stream such as `stdin()`: splits `input` at `\n`, removing a trailing `\r`; a line longer than `max_bytes` is an error.
export fn lines(input: ReadStream[Bytes], max_bytes: Int? = none) ReadStream[String]:
    return ReadStream[String](
        Lines(input, max_bytes, "".to_bytes(), 0, false, [], 0, false)
    )

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
        if self.at >= self.data.length(): return ok(none)

        stop := (self.at + self.chunk).min(self.data.length())
        piece := try self.data.slice(self.at, stop)
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
        item := try self.input.next()
        if value := item: return ok(self.f(value))

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
            item := try self.input.next()

            if value := item:
                if self.keep(value): return ok(value)
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
        if self.left <= 0: return ok(none)

        item := try self.input.next()
        self.left -= 1
        return ok(item)

    var fn close() Unit!:
        return self.input.close()

// A stream of at most the first `count` items of `input`, then the end: later items are never read, so `take` can
// end an endless stream. A failed read does not count as an item. A `count` of 0 or less is an empty stream. Closing it closes `input`.
export fn take[T](input: ReadStream[T], count: Int) ReadStream[T]:
    return ReadStream[T](Taker[T](input, count))

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
        if limit := max_items:
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
        if limit := max_bytes:
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
