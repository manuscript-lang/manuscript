import Iterator from "@std/core.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import ReadStream, WriteStream, IoError from "@std/io/io.ms"

# Buffered reading, buffered writing, and token scanning over byte streams.
#
# `BufferedReader` adds look-ahead (`peek`), delimiter reads (`read_until`), exact reads (`read_exact`) and
# single-scalar reads (`read_rune`) to any `ReadStream`, and is itself a `ReadStream`. `BufferedWriter` batches
# small writes into larger ones. `Scanner` walks a stream token by token (lines, words, scalars, a delimiter, or a
# split function you supply).
#
# ```manuscript
# import buffered_reader, scan, Split from "@std/io/buffered.ms"
# import from_bytes from "@std/io/streams.ms"
#
# fn words_of(text: String) List[String]:
#     var scanner = scan(from_bytes(text.to_bytes()), Split.Words)
#     var out = List[String]()
#     for word in scanner:
#         out.append(word.clone())
#     return out
# ```

# A read-ahead wrapper that lets callers inspect upcoming bytes before consuming them.
# Closing it closes the wrapped stream. The wrapper owns the stream it reads; keep it in a `var` binding.
export type BufferedReader:
    # The wrapped stream that supplies chunks; the reader owns it and closes it on close.
    input: ReadStream
    # Bytes read from `input` and not yet consumed start at `offset`.
    buffer: Bytes
    # Index in `buffer` of the next unconsumed byte.
    offset: Int
    # Chunk size requested from `input` on each refill.
    chunk: Int
    # True once `input` has reported end of stream.
    done: Bool

# Wraps `input` for look-ahead reads. `chunk_bytes` (default 64 KiB) is the size requested from `input` on each refill;
# a non-positive size makes reads fail with `InvalidInput`.
export fn buffered_reader(input: ReadStream, chunk_bytes: Int = 65536) BufferedReader:
    return BufferedReader(input, "".to_bytes(), 0, chunk_bytes, false)

impl BufferedReader:
    # Number of buffered bytes not yet consumed.
    fn buffered() Int:
        return self.buffer.length() - self.offset

    # Reads one more chunk into the buffer. Returns false at end of stream.
    var fn fill() Bool!IoError:
        if self.done: return ok(false)
        if self.chunk <= 0: return error(IoError.InvalidInput)

        let piece = try self.input.read(self.chunk)

        if piece.is_none():
            self.done = true
            return ok(false)

        let remaining = (self.buffer.slice(self.offset, self.buffer.length())).get()
        self.buffer = remaining.concat(piece.get())
        self.offset = 0
        return ok(true)

    # Makes at least `count` bytes available when the stream has them. Stops early only at end of stream.
    var fn ensure(count: Int) Unit!IoError:
        while self.buffered() < count:
            let more = try self.fill()
            if not more: break

        return ok(unit)

    # Drops `count` consumed bytes from the front of the buffer.
    var fn consume(count: Int) Unit:
        self.offset += count
        return unit

    # Returns up to `count` upcoming bytes without consuming them; fewer only at end of stream.
    var fn peek(count: Int) Bytes!IoError:
        if count < 0: return error(IoError.InvalidInput)

        try self.ensure(count)

        var size = count
        if self.buffered() < size: size = self.buffered()
        return ok((self.buffer.slice(self.offset, self.offset + size)).get())

    # Consumes and returns exactly `count` bytes. Ending before `count` bytes arrive returns `InvalidData`.
    var fn read_exact(count: Int) Bytes!IoError:
        let data = try self.peek(count)
        if data.length() < count: return error(IoError.InvalidData)

        self.consume(count)
        return ok(data)

    # Consumes and returns the bytes before the next `delimiter`, and consumes the delimiter itself.
    # Returns `none` at end of stream with nothing left; an unterminated tail is returned as the last result.
    # `max_bytes` bounds the bytes before the delimiter: a longer run returns `LimitExceeded`.
    var fn read_until(delimiter: UInt8, max_bytes: Int? = none) Bytes?!IoError:
        var searched = 0

        while true:
            if let found = self.buffer.index_of_byte(delimiter, self.offset + searched):
                let size = found - self.offset
                if max_bytes.is_some() and size > max_bytes.get(): return error(
                    IoError.LimitExceeded
                )

                let line = (self.buffer.slice(self.offset, found)).get()
                self.consume(size + 1)
                return ok(line)

            if max_bytes.is_some() and self.buffered() > max_bytes.get(): return error(
                IoError.LimitExceeded
            )

            searched = self.buffered()

            let more = try self.fill()
            if not more: break

        if self.buffered() == 0: return ok(none)

        let tail = (self.buffer.slice(self.offset, self.buffer.length())).get()
        self.consume(tail.length())
        return ok(tail)

    # Consumes and returns the next Unicode scalar as a one-scalar string, or `none` at end of stream.
    # Malformed UTF-8, or a stream that ends inside a scalar, returns `InvalidData`.
    var fn read_rune() String?!IoError:
        let lead = try self.peek(1)
        if lead.is_empty(): return ok(none)

        let first = lead.get(0, 0).to_int()
        var width = 1

        if first >= 240: width = 4
        else if first >= 224: width = 3
        else if first >= 192: width = 2

        let bytes = try self.peek(width)
        let text = bytes.decode_utf8()
        if text.is_none() or bytes.length() < width: return error(IoError.InvalidData)

        self.consume(width)
        return ok(text.get().clone())

    # Skips up to `count` bytes and returns how many were skipped; fewer only at end of stream.
    var fn skip(count: Int) Int!IoError:
        let data = try self.peek(count)
        self.consume(data.length())
        return ok(data.length())

impl ReadStream for BufferedReader:
    # Closes the wrapped stream; buffered bytes are dropped.
    var fn close() Unit:
        self.offset = self.buffer.length()
        self.done = true
        return self.input.close()

    # Returns buffered bytes first (at most `max_bytes`), otherwise one chunk from the wrapped stream.
    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        if max_bytes.is_some() and max_bytes.get() <= 0: return error(
            IoError.InvalidInput
        )

        if self.buffered() == 0:
            let more = try self.fill()
            if not more: return ok(none)

        var size = self.buffered()
        if max_bytes.is_some() and max_bytes.get() < size: size = max_bytes.get()

        let piece = (self.buffer.slice(self.offset, self.offset + size)).get()
        self.consume(size)
        return ok(piece)

# A write-behind wrapper that collects small writes and passes them on in larger pieces.
# Bytes reach `output` when the buffer holds `capacity` bytes, on `flush`, and on `close`. A failed
# close flush is dropped, so call `flush` first when the result matters.
export type BufferedWriter:
    # The wrapped stream that receives drained bytes; the writer owns it and closes it on close.
    output: WriteStream
    # Bytes accepted and not yet passed to `output`.
    pending: BytesBuilder
    # Number of bytes in `pending`.
    held: Int
    # Buffer size that triggers a write to `output`.
    capacity: Int

# Wraps `output` so many small writes become few large ones. `capacity` (default 64 KiB) is the buffer size in bytes.
export fn buffered_writer(output: WriteStream, capacity: Int = 65536) BufferedWriter:
    return BufferedWriter(output, BytesBuilder(), 0, capacity)

impl BufferedWriter:
    # Passes the held bytes to the wrapped stream without flushing that stream.
    var fn drain() Unit!IoError:
        if self.held == 0: return ok(unit)

        let data = self.pending.drain()
        self.held = 0
        return self.output.write_bytes(data)

impl WriteStream for BufferedWriter:
    # Flushes held bytes, then closes the wrapped stream.
    var fn close() Unit:
        let _ = self.drain()
        return self.output.close()

    # Writes held bytes to the wrapped stream, then flushes it.
    var fn flush() Unit!IoError:
        try self.drain()
        return self.output.flush()

    # Holds the UTF-8 bytes of `data`, with the rules of `write_bytes`.
    var fn write(data: String) Unit!IoError:
        return self.write_bytes(data.to_bytes())

    # Holds `data`; a piece that would not fit the buffer is written through after the held bytes.
    var fn write_bytes(data: Bytes) Unit!IoError:
        if self.held + data.length() > self.capacity:
            try self.drain()
        if data.length() >= self.capacity:
            return self.output.write_bytes(data)

        self.pending.append_bytes(data)
        self.held += data.length()
        return ok(unit)

# How a `Scanner` cuts its input into tokens.
export type Split:
    # Lines without their `\n` or `\r\n` terminator. A final unterminated line is a token.
    case Lines
    # Runs of non-space bytes; ASCII space, tab, newline, vertical tab, form feed and carriage return separate them.
    case Words
    # One Unicode scalar per token.
    case Runes
    # The text between occurrences of a non-empty delimiter.
    case Delimiter(
        # The separator; an empty delimiter makes the scan fail with `InvalidInput`.
        separator: String
    )
    # Tokens cut by your function, called with the unconsumed bytes and whether the stream has ended.
    case Custom(
        # Returns how many bytes to consume and the token, if any. See `SplitStep`.
        step: fn(Bytes, Bool) SplitStep
    )

# What a custom split function decides for the bytes it was shown.
export type SplitStep:
    # Bytes to consume. Zero with no token asks for more input; at end of stream it ends the scan.
    advance: Int
    # The token to yield, or none to yield nothing for these bytes.
    token: Bytes? = none

# A token iterator over a byte stream: `for line in scanner:`.
# Iteration stops at end of input or at the first error; `error()` tells the two apart. A token longer than
# `max_bytes` stops the scan with `LimitExceeded`. Tokens must be valid UTF-8, otherwise the scan stops with `InvalidData`.
export type Scanner:
    # The buffered input being scanned.
    reader: BufferedReader
    # How tokens are cut.
    split: Split
    # Per-token byte limit, or none for no limit.
    max_bytes: Int?
    # The error that ended the scan, if any.
    failure: IoError?

# Returns a scanner over `input`. Iterate a `var` scanner with `for` so `error()` can be read afterwards.
export fn scan(
    input: ReadStream,
    split: Split = Split.Lines,
    max_bytes: Int? = none
) Scanner:
    return Scanner(buffered_reader(input), split, max_bytes, none)

fn is_space(byte: UInt8) Bool:
    let value = byte.to_int()
    return value == 32 or (value >= 9 and value <= 13)

fn lines_step(data: Bytes, start: Int, at_eof: Bool) SplitStep:
    if let found = data.index_of_byte(10, start):
        var end = found
        if end > start and data.get(end - 1, 0).to_int() == 13: end -= 1
        return SplitStep(found + 1 - start, (data.slice(start, end)).get())

    if at_eof and data.length() > start:
        var end = data.length()
        if data.get(end - 1, 0).to_int() == 13: end -= 1
        return SplitStep(data.length() - start, (data.slice(start, end)).get())

    return SplitStep(0)

fn words_step(data: Bytes, start: Int, at_eof: Bool) SplitStep:
    var first = start
    while first < data.length() and is_space(data.get(first, 0)):
        first += 1

    var last = first
    while last < data.length() and not is_space(data.get(last, 0)):
        last += 1
    if last < data.length() or (at_eof and last > first):
        return SplitStep(last - start, (data.slice(first, last)).get())
    if at_eof: return SplitStep(data.length() - start)

    return SplitStep(0)

fn delimiter_step(data: Bytes, start: Int, mark: Bytes, at_eof: Bool) SplitStep:
    let window = (data.slice(start, data.length())).get()
    if let found = window.index_of(mark):
        return SplitStep(found + mark.length(), (window.slice(0, found)).get())
    if at_eof and window.length() > 0:
        return SplitStep(window.length(), window)

    return SplitStep(0)

impl Scanner:
    # Returns the I/O error that ended the scan, or none after a clean end of input.
    fn error() IoError?:
        return self.failure.clone()

    # Cuts the next token at the front of the buffer as a `SplitStep`.
    var fn cut(at_eof: Bool) SplitStep!IoError:
        match self.split:
            Lines: return ok(lines_step(self.reader.buffer, self.reader.offset, at_eof))
            Words: return ok(words_step(self.reader.buffer, self.reader.offset, at_eof))
            Runes:
                # read_rune consumes the scalar itself, so the step advances zero further bytes.
                let rune = try self.reader.read_rune()
                if rune.is_none(): return ok(SplitStep(0))

                return ok(SplitStep(0, rune.get().to_bytes()))
            Delimiter(separator):
                if separator.is_empty(): return error(IoError.InvalidInput)

                return ok(
                    delimiter_step(
                        self.reader.buffer, self.reader.offset, separator.to_bytes(),
                        at_eof
                    )
                )
            Custom(step):
                let window = (
                    self
                    .reader
                    .buffer
                    .slice(
                        self.reader.offset, self.reader.buffer.length()
                    )
                ).get()
                let result = step(window, at_eof)
                if result.advance < 0 or result.advance > window.length(): return error(
                    IoError.InvalidInput
                )

                return ok(result)

impl Iterator[String] for Scanner:
    # Returns the next token, or none at end of input or after an error (see `error()`).
    var fn next() String?:
        if self.failure.is_some(): return none

        while true:
            let at_eof = self.reader.done
            let size = self.reader.buffered()
            let outcome = self.cut(at_eof)

            if outcome.is_error():
                self.failure = outcome.err().clone()
                return none

            let step = outcome.get()

            if step.advance == 0 and step.token.is_none() and not at_eof:
                if self.max_bytes.is_some() and size > self.max_bytes.get():
                    self.failure = IoError.LimitExceeded
                    return none

                let more = self.reader.fill()

                if more.is_error():
                    self.failure = more.err().clone()
                    return none

                continue

            if step.advance == 0 and step.token.is_none():
                return none

            self.reader.consume(step.advance)
            if step.token.is_none(): continue

            let bytes = step.token.get()

            if self.max_bytes.is_some() and bytes.length() > self.max_bytes.get():
                self.failure = IoError.LimitExceeded
                return none

            let text = bytes.decode_utf8()

            if text.is_none():
                self.failure = IoError.InvalidData
                return none

            return text.get().clone()

        return none
