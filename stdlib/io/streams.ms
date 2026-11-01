import Bytes from "@std/bytes.ms"
import HashAlgorithm from "@std/crypto.ms"
import ReadStream, WriteStream, IoError, read_line from "@std/io/io.ms"

# Transform and composition helpers for byte streams. Each helper takes its input first, so
# flows read left to right: `source | map(upper) | take(1024) | copy(sink)`.
type BytesSource:
    data: Bytes
    offset: Int
    chunk: Int

impl ReadStream for BytesSource:
    var fn close() Unit:
        self.offset = self.data.length()
        return unit

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        if self.chunk <= 0: return error(IoError.InvalidInput)

        let remaining = self.data.length() - self.offset
        if remaining <= 0: return ok(none)

        let wanted = max_bytes.get(self.chunk)
        if wanted <= 0: return error(IoError.InvalidInput)

        var size = remaining
        if wanted < remaining: size = wanted

        let piece = (self.data.slice(self.offset, self.offset + size)).get()
        self.offset += size
        return ok(piece)

# Streams the bytes in `data` in chunks of at most `chunk_bytes` (default 64 KiB).
# A non-positive chunk size makes reads fail with InvalidInput.
export fn from_bytes(data: Bytes, chunk_bytes: Int = 65536) ReadStream:
    return BytesSource(data, 0, chunk_bytes)

type MappedStream:
    input: ReadStream
    transform: fn(Bytes) Bytes

impl ReadStream for MappedStream:
    var fn close() Unit:
        return self.input.close()

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        while true:
            let chunk = try self.input.read(max_bytes)

            if let bytes = chunk:
                let mapped = self.transform(bytes)
                if mapped.length() > 0: return ok(mapped)
            else:
                return ok(none)

        return ok(none)

# Applies `transform` to each chunk read from `input`. Chunks that transform to empty bytes are skipped.
# The result is only as stateless as `transform`: it sees chunk boundaries as `input` produces them.
# Closing the result closes `input`.
export fn map(input: ReadStream, transform: fn(Bytes) Bytes) ReadStream:
    return MappedStream(input, transform)

type LimitedStream:
    input: ReadStream
    remaining: Int

impl ReadStream for LimitedStream:
    var fn close() Unit:
        return self.input.close()

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        if self.remaining < 0: return error(IoError.InvalidInput)
        if self.remaining == 0: return ok(none)

        let wanted = max_bytes.get(self.remaining)
        let available = self.remaining
        var size = available
        if wanted < self.remaining: size = wanted

        let chunk = try self.input.read(size)

        if let bytes = chunk:
            self.remaining -= bytes.length()
            return ok(bytes)

        return ok(none)

# Ends the stream after `max_bytes` bytes without reading further from `input`.
# A negative limit makes reads fail with InvalidInput. Closing the result closes `input`.
export fn take(input: ReadStream, max_bytes: Int) ReadStream:
    return LimitedStream(input, max_bytes)

type ConcatStream:
    inputs: List[ReadStream]
    index: Int

impl ReadStream for ConcatStream:
    var fn close() Unit:
        let first = self.index
        var i = first

        while i < self.inputs.length():
            self.inputs[i].close()
            i += 1

        self.index = self.inputs.length()
        return unit

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        while self.index < self.inputs.length():
            # Read the stored stream in place: a stream is a value, so a local copy would lose its position.
            let chunk = try self.inputs[self.index].read(max_bytes)
            if let bytes = chunk: return ok(bytes)

            self.inputs[self.index].close()
            self.index += 1

        return ok(none)

# Reads each input to its end in order. Each input is closed when it ends or when the result is closed.
export fn concat(inputs: List[ReadStream]) ReadStream:
    return ConcatStream(inputs, 0)

type TeeStream:
    input: ReadStream
    sink: WriteStream

impl ReadStream for TeeStream:
    var fn close() Unit:
        return self.input.close()

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        let chunk = try self.input.read(max_bytes)

        if let bytes = chunk:
            try self.sink.write_bytes(bytes)
            return ok(bytes)

        return ok(none)

# Copies every chunk read from `input` to `sink` as it passes through. A sink failure fails the read.
# Closing the result closes `input` only; the caller owns `sink`.
export fn tee(input: ReadStream, sink: WriteStream) ReadStream:
    return TeeStream(input, sink)

type MappedWriter:
    output: WriteStream
    transform: fn(Bytes) Bytes

impl WriteStream for MappedWriter:
    var fn close() Unit:
        return self.output.close()

    var fn flush() Unit!IoError:
        return self.output.flush()

    var fn write(data: String) Unit!IoError:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!IoError:
        let mapped = self.transform(data)
        if mapped.length() == 0: return ok(unit)

        return self.output.write_bytes(mapped)

# Applies `transform` to each written chunk before writing to `output`. Empty results write nothing.
# Flush and close pass through to `output`.
export fn map_writer(output: WriteStream, transform: fn(Bytes) Bytes) WriteStream:
    return MappedWriter(output, transform)

# Reads `input` to its end and returns its digest, hashing chunk by chunk so memory stays bounded.
export fn digest(var input: ReadStream, algorithm: HashAlgorithm) Bytes!IoError:
    let hasher = algorithm.hasher()

    while true:
        let chunk = try input.read()

        if let bytes = chunk:
            hasher.update(bytes)
        else:
            return ok(hasher.finish())

    return ok(hasher.finish())

# Reads every remaining line from `input`, omitting line endings. `max_bytes` bounds each line, as in `read_line`.
export fn read_lines(input: ReadStream, max_bytes: Int?) List[String]!IoError:
    var lines = List[String]()

    while true:
        let line = try read_line(input, max_bytes)
        if line.is_none(): break

        lines.append(line.get().clone())

    return ok(lines)
