import Bytes, BytesBuilder from "@std/bytes.ms"
import ReadStream, WriteStream, Transform, through, stream, Source from "@std/io/io.ms"

// Steps for streams. Each takes its input first, so a pipeline is the `|` operator.

// Lines of bytes, without their `\n` or `\r\n`, cut only at line ends; the unterminated last line comes at the end.
type LineSplitter:
    tail: Bytes?
    max_bytes: Int?

impl LineSplitter:
    // Fails with `LimitExceeded` when a line of `size` bytes is longer than the limit.
    fn check(size: Int) Unit!:
        if let limit = self.max_bytes:
            if size > limit:
                return error(
                    Error(
                        "I/O: limit exceeded", kind: ErrorCategory.LimitExceeded
                    )
                )
        return ok(unit)

    // The held tail followed by `chunk`.
    var fn joined(chunk: Bytes) Bytes:
        if let held = self.tail:
            return held.concat(chunk)

        return chunk.clone()

impl Transform[Bytes, String] for LineSplitter:
    var fn feed(value: Bytes) List[String]!:
        var out: List[String] = []
        let data = self.joined(value)
        var start = 0

        while true:
            let end = data.index_of_byte(10, start)
            if end.is_none():
                break

            var stop = end.get()
            if stop > start and data.get(stop - 1, 0) == 13:
                stop -= 1
            try self.check(stop - start)

            let line = try data.slice(start, stop)
            out.append(line.decode_utf8().get(""))
            start = end.get() + 1

        if start < data.length():
            try self.check(data.length() - start)
            self.tail = try data.slice(start, data.length())
        else:
            self.tail = none

        return ok(out)

    var fn finish() List[String]!:
        var out: List[String] = []

        if let held = self.tail:
            out.append(held.decode_utf8().get(""))
            self.tail = none

        return ok(out)

// Reads lines of text from a byte stream such as `stdin()`: splits `input` at `\n`, removing a trailing `\r`; a line longer than `max_bytes` is an error.
export fn lines(input: ReadStream[Bytes], max_bytes: Int? = none) ReadStream[String]:
    return through[Bytes, String](input, LineSplitter(none, max_bytes))

// Items of a list, in order. The list is the stream's own.
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
    return stream[T](ListSource[T](reversed))

// Chunks of at most `chunk_bytes` bytes of `data`.
type BytesSource:
    data: Bytes
    at: Int
    chunk: Int

impl Source[Bytes] for BytesSource:
    var fn next() Bytes?!:
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

// A stream that yields `data` in chunks of at most `chunk_bytes` bytes and then ends.
export fn from_bytes(data: Bytes, chunk_bytes: Int = 65536) ReadStream[Bytes]:
    return stream[Bytes](BytesSource(data, 0, chunk_bytes))

type Mapper[T, U]:
    f: fn(T) U

impl Transform[T, U] for Mapper[T, U]:
    var fn feed(value: T) List[U]!:
        return ok([self.f(value)])

    var fn finish() List[U]!:
        return ok([])

// A stream of `f` applied to each item of `input`; closing it closes `input`.
export fn map[T, U](input: ReadStream[T], f: fn(T) U) ReadStream[U]:
    return through[T, U](input, Mapper[T, U](f))

// Every item of `input`, in order; more than `max_items` items is an error.
export fn collect[T](input: ReadStream[T], max_items: Int?) List[T]!:
    var source = input
    var items: List[T] = []

    while true:
        let step = try source.read().wait()

        if let item = step:
            items.append(item)
            if let limit = max_items:
                if items.length() > limit:
                    return error(
                        Error(
                            "I/O: limit exceeded", kind: ErrorCategory.LimitExceeded
                        )
                    )
        else:
            break

    return ok(items)

// All bytes of `input`; more than `max_bytes` bytes is an error.
export fn read_all(input: ReadStream[Bytes], max_bytes: Int?) Bytes!:
    var source = input
    var all = BytesBuilder()
    var total = 0

    while true:
        let step = try source.read().wait()

        if let chunk = step:
            all.append_bytes(chunk)
            total += chunk.length()
            if let limit = max_bytes:
                if total > limit:
                    return error(
                        Error(
                            "I/O: limit exceeded", kind: ErrorCategory.LimitExceeded
                        )
                    )
        else:
            break

    return ok(all.build())

// Moves every item of `input` to `output`; answers how many.
export fn copy[T](input: ReadStream[T], output: WriteStream[T]) Int!:
    var source = input
    var sink = output
    var count = 0

    while true:
        let step = try source.read().wait()

        if let item = step:
            try sink.write(item)
            count += 1
        else:
            break

    try sink.flush().wait()
    return ok(count)
