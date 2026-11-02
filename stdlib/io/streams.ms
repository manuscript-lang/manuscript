import Bytes from "@std/bytes.ms"
import HashAlgorithm from "@std/crypto.ms"
import ReadStream, WriteStream, IoError, read_line from "@std/io/io.ms"
import Channel, ChannelError from "@std/io/channels.ms"
import FileHandle, FileSystemError from "@std/os/fs.ms"

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

type FanOutWriter:
    outputs: List[WriteStream]

impl WriteStream for FanOutWriter:
    var fn close() Unit:
        for i in 0..self.outputs.length():
            self.outputs[i].close()
        return unit

    var fn flush() Unit!IoError:
        for i in 0..self.outputs.length():
            try self.outputs[i].flush()
        return ok(unit)

    var fn write(data: String) Unit!IoError:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!IoError:
        for i in 0..self.outputs.length():
            try self.outputs[i].write_bytes(data.clone())
        return ok(unit)

# Writes every chunk to each of `outputs` in order. The first failing output fails the write, leaving the later outputs without it.
# Flush and close pass through to every output.
export fn multi_writer(outputs: List[WriteStream]) WriteStream:
    return FanOutWriter(outputs)

type SectionStream:
    file: FileHandle
    offset: Int
    remaining: Int

impl ReadStream for SectionStream:
    var fn close() Unit:
        self.remaining = 0

        let _ = self.file.close()
        return unit

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        if self.remaining == 0: return ok(none)

        var wanted = max_bytes.get(65536)
        if wanted <= 0: return error(IoError.InvalidInput)

        if wanted > self.remaining: wanted = self.remaining

        let piece = self.file.read_at(self.offset, wanted)
        if piece.is_error(): return error(IoError.Failed(piece.err().message()))

        let bytes = piece.get().clone()

        if bytes.is_empty():
            self.remaining = 0
            return ok(none)

        self.offset += bytes.length()
        self.remaining -= bytes.length()
        return ok(bytes)

# Streams `length` bytes of `file` starting at byte `offset`, without moving the file's own position, so several sections
# of one file can be read independently. Fewer bytes arrive when the file ends first. The section reads through its own
# duplicate of the descriptor and closes it when closed; the caller still owns `file`.
# A negative offset or length, or a closed file, fails with the `FileSystemError` of the duplication.
export fn section(file: FileHandle, offset: Int, length: Int) ReadStream!FileSystemError:
    if offset < 0 or length < 0: return error(FileSystemError.InvalidInput)

    let copy = try file.clone()
    return ok(SectionStream(copy, offset, length))

fn channel_failure(failure: ChannelError) IoError:
    match failure:
        Closed: return IoError.Closed
        Broken(reason): return IoError.Failed(reason.clone())

type ChannelSource[In]:
    channel: Channel[In, Bytes]
    held: Bytes
    offset: Int

impl ReadStream for ChannelSource[In]:
    var fn close() Unit:
        self.channel.close()
        return unit

    var fn read(max_bytes: Int? = none) Bytes?!IoError:
        let wanted = max_bytes.get(65536)
        if wanted <= 0: return error(IoError.InvalidInput)

        if self.offset >= self.held.length():
            let next = self.channel.receive()
            if next.is_error(): return error(channel_failure(next.err()))
            if next.get().is_none(): return ok(none)

            self.held = next.get().get().clone()
            self.offset = 0

        let remaining = self.held.length() - self.offset
        var size = remaining
        if wanted < remaining: size = wanted

        let piece = (self.held.slice(self.offset, self.offset + size)).get()
        self.offset += size
        return ok(piece)

# Reads the byte chunks that the other end of a task channel sends: an in-memory pipe between tasks.
# The stream ends when the sender closes its end and every chunk was read. Closing it closes this end of the channel.
export fn channel_reader[In](channel: Channel[In, Bytes]) ReadStream:
    return ChannelSource(channel, "".to_bytes(), 0)

type ChannelSink[Out]:
    channel: Channel[Bytes, Out]

impl WriteStream for ChannelSink[Out]:
    var fn close() Unit:
        self.channel.close()
        return unit

    var fn flush() Unit!IoError:
        return ok(unit)

    var fn write(data: String) Unit!IoError:
        return self.write_bytes(data.to_bytes())

    var fn write_bytes(data: Bytes) Unit!IoError:
        if data.is_empty(): return ok(unit)

        let sent = self.channel.send(data)
        if sent.is_error(): return error(channel_failure(sent.err()))

        return ok(unit)

# Sends each write as one chunk over a task channel, so the other end reads it with `channel_reader`.
# A write waits while the reader has many unread chunks; once the reader closes, writes return `IoError.Closed`.
# Closing the writer closes this end of the channel, which ends the reader's stream.
export fn channel_writer[Out](channel: Channel[Bytes, Out]) WriteStream:
    return ChannelSink(channel)
