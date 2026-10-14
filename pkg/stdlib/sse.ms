# Server-Sent Events decoder implemented in Manuscript.
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {IoError, ReadStream} from "@std/io.ms"
import {ResponseBody} from "@std/http.ms"

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
    id: Optional[String]

# Optional byte budgets for one line and for one event.
export type SseLimits:
    # Largest line in bytes, excluding its line ending; none adds no budget.
    max_line_bytes: Optional[Int] = none
    # Largest total of all field lines in one event, excluding line endings and comments; none adds no budget.
    max_event_bytes: Optional[Int] = none

# Incremental decoder state. Create it with `decoder`, then pass chunks to `feed` and end with `finish`.
# Only `retry` is meant to be read; the other fields are internal state.
export type SseDecoder:
    # Limits fixed when the decoder was created.
    limits: SseLimits
    # The latest valid `retry:` value in milliseconds, or none if the stream sent none.
    retry: Optional[Int]
    # Internal: the last event ID, which persists across events.
    last_id: Optional[String]
    # Internal: bytes of the line being assembled.
    line: BytesBuilder
    # Internal: length of the line being assembled.
    line_bytes: Int
    # Internal: bytes counted against the event budget.
    event_bytes: Int
    # Internal: true when the previous byte was CR, so an immediately following LF is part of the same ending.
    carriage: Bool
    # Internal: true once the first line has been assembled and the byte order mark has been considered.
    started: Bool
    # Internal: true while field lines have arrived since the last blank line.
    open_block: Bool
    # Internal: the pending `event:` value, empty when unset.
    event_type: String
    # Internal: the pending `data:` lines.
    data: List[String]
    # Internal: the first failure, repeated by later calls.
    failure: Optional[SseError]
    # Internal: true after `finish`.
    closed: Bool

impl Error for SseError:
    # Returns a fixed diagnostic that does not echo stream contents.
    fn message() -> String:
        match self:
            InvalidInput: return "SSE invalid input"
            InvalidData: return "SSE line is not valid UTF-8"
            LimitExceeded: return "SSE limit exceeded"
            Truncated: return "SSE stream ended inside an event"
            ReadFailed(cause): return "SSE read failed: {cause.message()}"

# Creates a decoder. Supplied limits must be positive.
export fn decoder(limits: SseLimits = SseLimits()) -> Result[SseDecoder, SseError]:
    if not positive(limits.max_line_bytes): return error(SseError.InvalidInput)
    if not positive(limits.max_event_bytes): return error(SseError.InvalidInput)

    return ok(
        SseDecoder(
            limits: limits,
            retry: none,
            last_id: none,
            line: BytesBuilder(),
            line_bytes: 0,
            event_bytes: 0,
            carriage: false,
            started: false,
            open_block: false,
            event_type: "",
            data: List[String](),
            failure: none,
            closed: false
        )
    )

fn positive(limit: Optional[Int]) -> Bool:
    match limit:
        none: return true
        some(maximum): return maximum > 0

fn exceeds(value: Int, limit: Optional[Int]) -> Bool:
    match limit:
        none: return false
        some(maximum): return value > maximum

# Decodes one chunk and returns the events it completed, in order.
# Chunks may split any line, line ending or UTF-8 scalar. An error is final for the decoder.
export fn feed(decoder: SseDecoder, chunk: Bytes) -> Result[List[SseEvent], SseError]:
    let events = List[SseEvent]()

    if decoder.failure.is_some(): return error(decoder.failure.unwrap())

    if decoder.closed: return error(SseError.InvalidInput)

    var index = 0
    let total = chunk.length()

    while index < total:
        let step = consume(
            decoder: decoder,
            byte: chunk.at(index).unwrap(),
            events: events
        )
        index = index + 1

        if step.is_error():
            let failure = step.unwrap_error()
            decoder.failure = some(failure)
            return error(failure)

    return ok(events)

# Ends the stream. A stream with no partial line and no unfinished event ends cleanly;
# otherwise the result is Truncated and the unfinished event is never dispatched.
export fn finish(decoder: SseDecoder) -> Result[Unit, SseError]:
    if decoder.failure.is_some(): return error(decoder.failure.unwrap())

    if decoder.closed: return error(SseError.InvalidInput)

    decoder.closed = true

    if decoder.line_bytes > 0 or decoder.open_block:
        decoder.failure = some(SseError.Truncated)
        return error(SseError.Truncated)

    return ok(unit)

fn consume(
    decoder: SseDecoder,
    byte: Int,
    events: List[SseEvent]
) -> Result[Unit, SseError]:
    let after_carriage = decoder.carriage
    decoder.carriage = false

    if byte == 10 and after_carriage: return ok(unit)

    if byte == 10 or byte == 13:
        decoder.carriage = byte == 13
        return end_line(decoder: decoder, events: events)

    decoder.line.append(byte)
    decoder.line_bytes = decoder.line_bytes + 1

    if exceeds(value: decoder.line_bytes, limit: decoder.limits.max_line_bytes): return error(
        SseError.LimitExceeded
    )

    return ok(unit)

fn end_line(decoder: SseDecoder, events: List[SseEvent]) -> Result[Unit, SseError]:
    var bytes = decoder.line.freeze()
    decoder.line = BytesBuilder()
    decoder.line_bytes = 0

    if not decoder.started:
        decoder.started = true

        if bytes.starts_with("\u{feff}".to_bytes()): bytes = (
            bytes
            .slice(3, bytes.length())
            .unwrap()
        )

    if bytes.is_empty():
        dispatch(decoder: decoder, events: events)
        return ok(unit)

    let text = bytes.to_text()
    if text.is_none(): return error(SseError.InvalidData)

    let line = text.unwrap()
    if line.starts_with(":"): return ok(unit)

    decoder.event_bytes = decoder.event_bytes + bytes.length()
    if exceeds(value: decoder.event_bytes, limit: decoder.limits.max_event_bytes): return error(
        SseError.LimitExceeded
    )

    decoder.open_block = true
    apply(decoder: decoder, line: line)
    return ok(unit)

fn apply(decoder: SseDecoder, line: String) -> Unit:
    var name = line
    var value = ""
    let colon = line.index_of(":")

    if colon.is_some():
        name = line.slice(0, colon.unwrap()).unwrap()
        value = line.slice(colon.unwrap() + 1, line.length()).unwrap()

        if value.starts_with(" "): value = value.slice(1, value.length()).unwrap()

    if name == "event": decoder.event_type = value
    else if name == "data": decoder.data.append(value)
    else if name == "id": identify(decoder: decoder, value: value)
    else if name == "retry": reconnect(decoder: decoder, value: value)

# An ID containing NUL is ignored, so it neither replaces nor clears the last ID.
fn identify(decoder: SseDecoder, value: String) -> Unit:
    if value.to_bytes().contains("\u{0}".to_bytes()): return unit

    decoder.last_id = some(value)

# Only ASCII digits form a retry time; overflow and signs are ignored.
fn reconnect(decoder: SseDecoder, value: String) -> Unit:
    if (value.is_empty() or value.starts_with("-") or value.starts_with("+")): return unit

    let milliseconds = value.parse_int()

    if milliseconds.is_some(): decoder.retry = milliseconds

fn dispatch(decoder: SseDecoder, events: List[SseEvent]) -> Unit:
    if decoder.data.length() > 0:
        var name = decoder.event_type

        if name == "": name = "message"

        events.append(
            SseEvent(
                event: name,
                data: decoder.data.join("\n"),
                id: decoder.last_id
            )
        )

    decoder.event_type = ""
    decoder.data = List[String]()
    decoder.event_bytes = 0
    decoder.open_block = false

type BorrowedBody:
    body: ResponseBody

impl ReadStream for BorrowedBody:
    fn close() -> Unit:
        return unit

    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        return self.body.read(max_bytes: max_bytes)

# Views an HTTP response body as a ReadStream that the response keeps owning.
# Closing the view does nothing, so close the body itself, usually with `with`.
export fn borrow_body(body: ResponseBody) -> ReadStream:
    return ReadStream(value: BorrowedBody(body: body))

# Pulls events from a borrowed ReadStream. The reader never closes the stream:
# its owner closes it, and closing it makes a blocked read fail with ReadFailed.
export type SseReader:
    # The borrowed stream, such as an HTTP response body.
    input: ReadStream
    # The decoder, whose `retry` is readable between events.
    decoder: SseDecoder
    # Internal: events decoded but not yet returned.
    ready: List[SseEvent]
    # Internal: index of the next ready event.
    next: Int
    # Internal: requested read size, none for the stream default.
    chunk_bytes: Optional[Int]
    # Internal: true after a clean end of stream.
    finished: Bool

# Wraps a stream in an event reader. Supplied limits and chunk size must be positive.
export fn reader(
    input: ReadStream,
    limits: SseLimits = SseLimits(),
    chunk_bytes: Optional[Int] = none
) -> Result[SseReader, SseError]:
    if not positive(chunk_bytes): return error(SseError.InvalidInput)

    let created = try decoder(limits: limits)

    return ok(
        SseReader(
            input: input,
            decoder: created,
            ready: List[SseEvent](),
            next: 0,
            chunk_bytes: chunk_bytes,
            finished: false
        )
    )

# Returns the next event, or none after a clean end of stream.
# A read failure, malformed line, exceeded limit or truncated event is an error.
export fn next_event(reader: SseReader) -> Result[Optional[SseEvent], SseError]:
    while true:
        if reader.next < reader.ready.length():
            let event = reader.ready.at(reader.next).unwrap()
            reader.next = reader.next + 1
            return ok(some(event))

        if reader.finished: return ok(none)

        reader.ready = List[SseEvent]()
        reader.next = 0

        let read = reader.input.read(max_bytes: reader.chunk_bytes)
        if read.is_error(): return error(
            SseError.ReadFailed(cause: read.unwrap_error())
        )

        let chunk = read.unwrap()

        if chunk.is_some():
            reader.ready = try feed(decoder: reader.decoder, chunk: chunk.unwrap())
        else:
            try finish(decoder: reader.decoder)
            reader.finished = true

    return ok(none)
