import Bytes from "@std/bytes.ms"
import ReadStream, WriteStream, IoError, read_all from "@std/io/io.ms"
import fail from "@std/test/test.ms"

# Misbehaving streams for testing code that reads and writes. Each wrapper takes its input first, like the
# helpers in `@std/io/streams.ms`, so `from_bytes(data) | one_byte` is a reader that trickles.
# `check_reader` is the conformance check for a `ReadStream` you wrote.
type OneByte:
    input: ReadStream

impl ReadStream for OneByte:
    var fn close() Unit:
        return self.input.close()

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        if let wanted = max_bytes:
            if wanted <= 0: return error(IoError.InvalidInput)
        return self.input.read(1)

# Returns `input` limited to one byte per read, which exposes code that assumes a read fills its buffer.
export fn one_byte(input: ReadStream) ReadStream:
    return OneByte(input)

type FailAfter:
    input: ReadStream
    remaining: Int
    cause: IoError

impl ReadStream for FailAfter:
    var fn close() Unit:
        return self.input.close()

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        if self.remaining <= 0: return error(self.cause.clone())

        var size = self.remaining

        if let wanted = max_bytes:
            if wanted <= 0: return error(IoError.InvalidInput)

            if wanted < size: size = wanted

        let chunk = try self.input.read(size)
        if let bytes = chunk:
            self.remaining -= bytes.length()
        return ok(chunk)

# Returns `input` that delivers `after` bytes and then fails every read with `cause`, even if `input` has ended.
# Use it to check that a parser reports a truncated or broken source instead of treating it as clean end of input.
export fn fail_after(input: ReadStream, after: Int, cause: IoError) ReadStream:
    return FailAfter(input, after, cause)

type FailingWriter:
    output: WriteStream
    remaining: Int
    cause: IoError

impl WriteStream for FailingWriter:
    var fn close() Unit:
        return self.output.close()

    var fn flush() Unit!IoError:
        return self.output.flush()

    var fn write(data: String) Unit!IoError:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!IoError:
        let size = data.length()

        if size <= self.remaining:
            self.remaining -= size
            return self.output.write_bytes(data)

        # Like a full disk: the prefix that fits is written, then the write fails.
        let prefix = self.remaining
        self.remaining = 0
        if prefix > 0:
            try self.output.write_bytes(data.slice(0, prefix).get())
        return error(self.cause.clone())

# Returns a writer that passes `after` bytes through to `output`, writes the prefix of the write that crosses the limit,
# and then fails that write and every later one with `cause`. Use it to check error handling on a full disk or closed pipe.
export fn fail_writer_after(output: WriteStream, after: Int, cause: IoError) WriteStream:
    return FailingWriter(output, after, cause)

# Checks that `make` builds a well-behaved `ReadStream` over exactly `expected`: whole reads, one-byte reads, a chunk size
# that is respected, and an end of input that stays ended. `make` is called once per check so each starts from the beginning.
export fn check_reader(make: fn() ReadStream, expected: Bytes) Unit!:
    var whole = make()
    let all = read_all(whole, none)
    whole.close()
    if all.is_error():
        return fail("check_reader: reading everything failed")
    if all.get() != expected:
        return fail(
            "check_reader: read {all.get().length()} bytes, expected {expected.length()}; content differs"
        )

    var trickle = one_byte(make())
    let slow = read_all(trickle, none)
    trickle.close()
    if slow.is_error():
        return fail("check_reader: one-byte reads failed")
    if slow.get() != expected:
        return fail("check_reader: one-byte reads returned different content")

    var bounded = make()
    var total = 0

    while true:
        let chunk = bounded.read(3)

        if chunk.is_error():
            bounded.close()
            return fail("check_reader: bounded read failed")

        let piece = chunk.get()
        if piece.is_none():
            break

        if piece.get().length() > 3:
            bounded.close()
            return fail("check_reader: read(3) returned {piece.get().length()} bytes")

        total += piece.get().length()

    let again = bounded.read(3)
    bounded.close()
    if again.is_error() or again.get().is_some():
        return fail("check_reader: a read after end of input must return none again")
    if total != expected.length():
        return fail(
            "check_reader: bounded reads returned {total} bytes, expected {expected.length()}"
        )

    return ok(unit)
