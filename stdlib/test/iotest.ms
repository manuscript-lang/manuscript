import (
    Bytes from "@std/bytes.ms",
    ReadStream, WriteStream, Source, Sink from "@std/io/io.ms",
    Promise from "@std/concurrency/promise.ms",
    read_all, from_bytes from "@std/io/streams.ms",
    fail from "@std/test/test.ms",
)

/*
Misbehaving streams for testing code that reads and writes. Each wrapper takes its input first, like the
helpers in `@std/io/streams.ms`, so `from_bytes(data) | one_byte` is a reader that trickles.
`check_reader` is the conformance check for a `ReadStream[Bytes]` you wrote.
*/
type OneByte:
    input: ReadStream[Bytes]
    held: Bytes?

impl Source[Bytes] for OneByte:
    var fn next() Bytes?!:
        var data = "".to_bytes()

        if held := self.held:
            data = held.clone()
        else:
            fresh := try self.input.next()
            if fresh.is_none(): return ok(none)

            data = fresh.get().clone()

        if data.length() <= 1:
            self.held = none
            return ok(data)

        self.held = try data.slice(1, data.length())
        return ok(try data.slice(0, 1))

    var fn close() Unit!:
        return self.input.close()

// Returns `input` limited to one byte per read, which exposes code that assumes a read fills its buffer.
export fn one_byte(input: ReadStream[Bytes]) ReadStream[Bytes]:
    return ReadStream[Bytes](OneByte(input, none))

type FailAfter:
    input: ReadStream[Bytes]
    remaining: Int
    cause: Error

impl Source[Bytes] for FailAfter:
    var fn next() Bytes?!:
        if self.remaining <= 0: return error(self.cause.clone())

        chunk := try self.input.next()

        if data := chunk:
            if data.length() > self.remaining:
                head := try data.slice(0, self.remaining)
                self.remaining = 0
                return ok(head)

            self.remaining -= data.length()

        return ok(chunk)

    var fn close() Unit!:
        return self.input.close()

// Returns `input` that delivers `after` bytes and then fails every read with `cause`, even if `input` has ended.
// Use it to check that a parser reports a truncated or broken source instead of treating it as clean end of input.
export fn fail_after(
    input: ReadStream[Bytes],
    after: Int,
    cause: Error
) ReadStream[Bytes]:
    return ReadStream[Bytes](FailAfter(input, after, cause))

type FailingSink:
    output: WriteStream[Bytes]
    remaining: Int
    cause: Error

impl Sink[Bytes] for FailingSink:
    var fn write(value: Bytes) Unit!:
        size := value.length()

        if size <= self.remaining:
            self.remaining -= size
            return self.output.write(value)

        // Like a full disk: the prefix that fits is written, then the write fails.
        prefix := self.remaining
        self.remaining = 0
        if prefix > 0:
            try self.output.write(try value.slice(0, prefix))
        return error(self.cause.clone())

    var fn flush() Unit!:
        return self.output.flush()

    var fn close() Unit!:
        return self.output.close()

// Returns a writer that passes `after` bytes through to `output`, writes the prefix of the write that crosses the limit,
// and then fails that write and every later one with `cause`. Use it to check error handling on a full disk or closed pipe.
export fn fail_writer_after(
    output: WriteStream[Bytes],
    after: Int,
    cause: Error
) WriteStream[Bytes]:
    return WriteStream[Bytes](FailingSink(output, after, cause))

// Checks that `make` builds a well-behaved `ReadStream[Bytes]` over exactly `expected`: whole reads, one-byte reads, and
// an end of input that stays ended. `make` is called once per check so each starts from the beginning.
export fn check_reader(make: fn() ReadStream[Bytes], expected: Bytes) Unit!:
    all := read_all(make())
    if all.is_error(): return fail("check_reader: reading everything failed")
    if all.get() != expected:
        return fail(
            "check_reader: read {all.get().length()} bytes, expected {expected.length()}; content differs"
        )

    slow := read_all(one_byte(make()))
    if slow.is_error(): return fail("check_reader: one-byte reads failed")
    if slow.get() != expected:
        return fail("check_reader: one-byte reads returned different content")

    var again = make()
    var total = 0

    while true:
        chunk := again.next()
        if chunk.is_error(): return fail("check_reader: a read failed")

        piece := chunk.get()
        if piece.is_none(): break

        total += piece.get().length()

    after_end := again.next()
    if after_end.is_error() or after_end.get().is_some():
        return fail("check_reader: a read after end of input must return none again")
    if total != expected.length():
        return fail(
            "check_reader: chunked reads returned {total} bytes, expected {expected.length()}"
        )
