# Server-Sent Events decoder implemented in Manuscript.
import Bytes, BytesBuilder from "@std/bytes.ms"
import IoError, ReadStream from "@std/io.ms"
import ResponseBody from "@std/http.ms"
import Closeable from "@std/core.ms"

# Errors returned for invalid input, malformed or oversized event streams, and failed reads.
export type SseError:
    # A supplied limit or chunk size is not positive, or the decoder was used after `finish`.
    case InvalidInput
    # A line is not valid UTF-8 text.
    case InvalidData
    # A line or an event exceeds a supplied byte budget.
    case LimitExceeded
    # The stream ended inside a line or before the blank line that completes an event.
    case Truncated
    # The underlying stream failed to read; the cause keeps its original I/O case.
    case ReadFailed(
        # The error returned by the borrowed stream.
        cause: IoError
    )

# One dispatched event, with the `message` type used when no `event:` field was sent.
export type SseEvent:
    # The event type from the last `event:` field, or `message`.
    event: String
    # Every `data:` line of the event joined with LF; a bare `data:` line gives an empty line.
    data: String
    # The last event ID in effect when the event was dispatched, or none if the stream never set one.
    id: String?

# Optional byte budgets for one line and for one event.
export type SseLimits:
    # Largest line in bytes, excluding its line ending; none adds no budget.
    max_line_bytes: Int?
    # Largest total of all field lines in one event, excluding line endings and comments; none adds no budget.
    max_event_bytes: Int?

# Decodes a Server-Sent Events stream from byte chunks of any size.
#
# Chunks may split any line, line ending or UTF-8 scalar. The decoder never reads,
# closes, or owns a stream.
export interface SseDecoder:
    # Decodes one chunk and returns the events it completed, in order.
    # An error is final for the decoder, which returns it again on later calls.
    var fn feed(chunk: Bytes) Result[List[SseEvent], SseError]
    # Ends the stream. A stream with no partial line and no unfinished event ends cleanly;
    # otherwise the result is Truncated and the unfinished event is never dispatched.
    var fn finish() Result[Unit, SseError]
    # Returns the latest valid `retry:` value in milliseconds, or none if the stream sent none.
    fn retry() Int?

# Internal decoder state behind `SseDecoder`.
type Decoder:
    # Limits fixed when the decoder was created.
    limits: SseLimits
    # The latest valid `retry:` value in milliseconds, or none if the stream sent none.
    retry_ms: Int?
    # Internal: the last event ID, which persists across events.
    last_id: String?
    # Internal: bytes of the line being assembled.
    line: BytesBuilder
    # Internal: length of the line being assembled.
    line_bytes: Int
    # Internal: bytes counted against the event budget.
    event_bytes: Int
    # Internal: True when the previous byte was CR, so an immediately following LF is part of the same ending.
    carriage: Bool
    # Internal: True once the first line has been assembled and the byte order mark has been considered.
    started: Bool
    # Internal: True while field lines have arrived since the last blank line.
    open_block: Bool
    # Internal: the pending `event:` value, empty when unset.
    event_type: String
    # Internal: the pending `data:` lines.
    data: List[String]
    # Internal: the first failure, repeated by later calls.
    failure: SseError?
    # Internal: True after `finish`.
    closed: Bool

impl Error for SseError:
    # Returns a fixed diagnostic that does not echo stream contents.
    fn message() String:
        match self:
            InvalidInput: return "SSE invalid input"
            InvalidData: return "SSE line is not valid UTF-8"
            LimitExceeded: return "SSE limit exceeded"
            Truncated: return "SSE stream ended inside an event"
            ReadFailed(cause): return "SSE read failed: {cause.message()}"

# Creates a decoder. Supplied limits must be positive.
export fn decoder(limits: SseLimits = SseLimits()) Result[SseDecoder, SseError]:
    if not positive(limits.max_line_bytes): return error(SseError.InvalidInput)
    if not positive(limits.max_event_bytes): return error(SseError.InvalidInput)

    return ok(
        Decoder(
            limits: limits, retry_ms: none, last_id: none, line: BytesBuilder(),
            line_bytes: 0, event_bytes: 0, carriage: false, started: false,
            open_block: false, event_type: "", data: List[String](), failure: none,
            closed: false
        )
    )

fn positive(limit: Int?) Bool:
    if let maximum = limit:
        return maximum > 0

    return true

fn exceeds(value: Int, limit: Int?) Bool:
    if let maximum = limit:
        return value > maximum

    return false

impl SseDecoder for Decoder:
    var fn feed(chunk: Bytes) Result[List[SseEvent], SseError]:
        var events = List[SseEvent]()
        if let failure = self.failure: return error(failure.clone())
        if self.closed: return error(SseError.InvalidInput)

        let total = chunk.length()
        var start = 0
        var lf = chunk.index_of_byte(10, 0).get(total)
        var cr = chunk.index_of_byte(13, 0).get(total)

        while start < total:
            var end = lf
            if cr < end: end = cr
            if end == total: break

            let byte = chunk.get(end)

            if byte == 10 and self.carriage and end == start:
                self.carriage = false
            else:
                let step = complete(var self, chunk, start, end, var events)
                self.carriage = byte == 13

                if step.is_error():
                    let failure = step.err().clone()
                    self.failure = failure.clone()
                    return error(failure)

            start = end + 1
            if lf < start: lf = chunk.index_of_byte(10, start).get(total)
            if cr < start: cr = chunk.index_of_byte(13, start).get(total)

        if start < total:
            self.carriage = false

            let step = hold(var self, chunk.slice(start, total).get())

            if step.is_error():
                let failure = step.err().clone()
                self.failure = failure.clone()
                return error(failure)

        return ok(events)

    var fn finish() Result[Unit, SseError]:
        if let failure = self.failure: return error(failure.clone())
        if self.closed: return error(SseError.InvalidInput)

        self.closed = true

        if self.line_bytes > 0 or self.open_block:
            self.failure = SseError.Truncated
            return error(SseError.Truncated)

        return ok(unit)

    fn retry() Int?:
        return self.retry_ms

# Buffers the unterminated tail of a chunk as part of the line being assembled.
fn hold(var decoder: Decoder, segment: Bytes) Result[Unit, SseError]:
    decoder.line_bytes += segment.length()
    if exceeds(decoder.line_bytes, decoder.limits.max_line_bytes): return error(
        SseError.LimitExceeded
    )

    decoder.line.append_bytes(segment)
    return ok(unit)

# Finishes the line `chunk[start, end)` that ends at a terminator, joining it with any bytes held from earlier chunks.
fn complete(
    var decoder: Decoder, chunk: Bytes, start: Int, end: Int, var events: List[SseEvent]
) Result[Unit, SseError]:
    if decoder.line_bytes == 0:
        if exceeds(end - start, decoder.limits.max_line_bytes): return error(
            SseError.LimitExceeded
        )

        return end_line(var decoder, chunk, start, end, var events)

    try hold(var decoder, chunk.slice(start, end).get())

    let joined = decoder.line.drain()
    decoder.line_bytes = 0
    return end_line(var decoder, joined, 0, joined.length(), var events)

fn end_line(
    var decoder: Decoder, bytes: Bytes, start: Int, end: Int, var events: List[SseEvent]
) Result[Unit, SseError]:
    var from = start

    if not decoder.started:
        decoder.started = true
        if bytes.slice(start, end).get().starts_with("\u{feff}".to_bytes()): from += 3

    if from == end:
        dispatch(var decoder, var events)
        return ok(unit)

    let line = try bytes.decode_utf8_range(from, end).ok_or(SseError.InvalidData)
    if line.starts_with(":"): return ok(unit)

    decoder.event_bytes += end - from
    if exceeds(decoder.event_bytes, decoder.limits.max_event_bytes): return error(
        SseError.LimitExceeded
    )

    decoder.open_block = true
    apply(var decoder, line)
    return ok(unit)

fn apply(var decoder: Decoder, line: String) Unit:
    if line.starts_with("data:"):
        decoder.data.append(value_after(line, 5, line.starts_with("data: ")))
    else if line.starts_with("event:"):
        decoder.event_type = value_after(line, 6, line.starts_with("event: "))
    else if line.starts_with("id:"):
        identify(var decoder, value_after(line, 3, line.starts_with("id: ")))
    else if line.starts_with("retry:"):
        reconnect(var decoder, value_after(line, 6, line.starts_with("retry: ")))
    else: apply_other(var decoder, line)

# The value after the colon, skipping one leading space when `spaced`.
fn value_after(line: String, colon_end: Int, spaced: Bool) String:
    if spaced: return line.slice(colon_end + 1, line.length()).get()

    return line.slice(colon_end, line.length()).get()

# Lines without a colon name a field with an empty value; other names are ignored.
fn apply_other(var decoder: Decoder, line: String) Unit:
    if line.index_of(":").is_some(): return unit

    if line == "data": decoder.data.append("")
    else if line == "event": decoder.event_type = ""
    else if line == "id": identify(var decoder, "")
    else if line == "retry": reconnect(var decoder, "")

# An ID containing NUL is ignored, so it neither replaces nor clears the last ID.
fn identify(var decoder: Decoder, value: String) Unit:
    if value.to_bytes().contains("\u{0}".to_bytes()): return unit

    decoder.last_id = value

# Only ASCII digits form a retry time; overflow and signs are ignored.
fn reconnect(var decoder: Decoder, value: String) Unit:
    if (value.is_empty() or value.starts_with("-") or value.starts_with("+")): return unit

    let milliseconds = value.parse_int()
    if milliseconds.is_some(): decoder.retry_ms = milliseconds

fn dispatch(var decoder: Decoder, var events: List[SseEvent]) Unit:
    if decoder.data.length() > 0:
        var name = decoder.event_type.clone()
        if name == "": name = "message"
        events.append(SseEvent(name, decoder.data.join("\n"), decoder.last_id.clone()))

    decoder.event_type = ""
    decoder.data = List[String]()
    decoder.event_bytes = 0
    decoder.open_block = false

type OwnedBody:
    body: ResponseBody

impl ReadStream for OwnedBody:
    var fn close() Unit:
        self.body.close()

    var fn read(max_bytes: Int? = none) Result[Bytes?, IoError]:
        return self.body.read(max_bytes)

# Turns an HTTP response body into a ReadStream that owns it. Closing the stream closes the body.
export fn body_stream(body: ResponseBody) ReadStream:
    return OwnedBody(body)

# Pulls events from a ReadStream it owns. Closing the reader closes the stream, and closing it
# makes a blocked read fail with ReadFailed.
export type SseReader:
    # The stream, such as an HTTP response body made by `body_stream`.
    input: ReadStream
    # The decoder, whose `retry()` is readable between events.
    decoder: SseDecoder
    # Internal: events decoded but not yet returned.
    ready: List[SseEvent]
    # Internal: index of the next ready event.
    next: Int
    # Internal: requested read size, none for the stream default.
    chunk_bytes: Int?
    # Internal: True after a clean end of stream.
    finished: Bool

# Takes a stream and wraps it in an event reader. Supplied limits and chunk size must be positive.
export fn reader(
    input: ReadStream,
    limits: SseLimits = SseLimits(),
    chunk_bytes: Int?
) Result[SseReader, SseError]:
    if not positive(chunk_bytes): return error(SseError.InvalidInput)

    let created = try decoder(limits)
    return ok(
        SseReader(
            input: input, decoder: created, ready: List[SseEvent](), next: 0,
            chunk_bytes: chunk_bytes, finished: false
        )
    )

impl Closeable for SseReader:
    # Closes the stream the reader owns; reads after a close fail with ReadFailed.
    var fn close() Unit:
        self.input.close()

# Returns the next event, or none after a clean end of stream.
# A read failure, malformed line, exceeded limit or truncated event is an error.
export fn next_event(var reader: SseReader) Result[SseEvent?, SseError]:
    while true:
        if reader.next < reader.ready.length():
            let event = reader.ready.get(reader.next)
            reader.next += 1
            return ok(event.clone())

        if reader.finished: return ok(none)

        reader.ready = List[SseEvent]()
        reader.next = 0

        var chunk: Bytes? = none

        match reader.input.read(reader.chunk_bytes):
            ok(value): chunk = value
            error(cause): return error(SseError.ReadFailed(cause: cause))

        if let bytes = chunk:
            reader.ready = try reader.decoder.feed(bytes)
        else:
            try reader.decoder.finish()
            reader.finished = true
