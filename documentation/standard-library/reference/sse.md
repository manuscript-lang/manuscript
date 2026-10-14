+++
title = "sse"
+++

# @std/sse.ms

Import each required symbol with `import Name from "@std/sse.ms"`.

## SseDecoder {data-api-kind="Record"}

Incremental decoder state. Create it with `decoder`, then pass chunks to `feed` and end with `finish`.
Only `retry` is meant to be read; the other fields are internal state.

```manuscript
type SseDecoder:
    limits: SseLimits
    retry: Optional[Int]
    last_id: Optional[String]
    line: BytesBuilder
    line_bytes: Int
    event_bytes: Int
    carriage: Bool
    started: Bool
    open_block: Bool
    event_type: String
    data: List[String]
    failure: Optional[SseError]
    closed: Bool
```

### SseDecoder.carriage

Internal: true when the previous byte was CR, so an immediately following LF is part of the same ending.

```manuscript
carriage: Bool
```

### SseDecoder.closed

Internal: true after `finish`.

```manuscript
closed: Bool
```

### SseDecoder.data

Internal: the pending `data:` lines.

```manuscript
data: List[String]
```

### SseDecoder.event_bytes

Internal: bytes counted against the event budget.

```manuscript
event_bytes: Int
```

### SseDecoder.event_type

Internal: the pending `event:` value, empty when unset.

```manuscript
event_type: String
```

### SseDecoder.failure

Internal: the first failure, repeated by later calls.

```manuscript
failure: Optional[SseError]
```

### SseDecoder.last_id

Internal: the last event ID, which persists across events.

```manuscript
last_id: Optional[String]
```

### SseDecoder.limits

Limits fixed when the decoder was created.

```manuscript
limits: SseLimits
```

### SseDecoder.line

Internal: bytes of the line being assembled.

```manuscript
line: BytesBuilder
```

### SseDecoder.line_bytes

Internal: length of the line being assembled.

```manuscript
line_bytes: Int
```

### SseDecoder.open_block

Internal: true while field lines have arrived since the last blank line.

```manuscript
open_block: Bool
```

### SseDecoder.retry

The latest valid `retry:` value in milliseconds, or none if the stream sent none.

```manuscript
retry: Optional[Int]
```

### SseDecoder.started

Internal: true once the first line has been assembled and the byte order mark has been considered.

```manuscript
started: Bool
```

## SseError {data-api-kind="Alternative"}

Errors returned for invalid input, malformed or oversized event streams, and failed reads.

```manuscript
type SseError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Truncated
    case ReadFailed(cause: IoError)
```

```manuscript
impl Error for SseError:
    fn message() -> String:
```

### SseError.InvalidData

A line is not valid UTF-8 text.

```manuscript
case InvalidData
```

### SseError.InvalidInput

A supplied limit or chunk size is not positive, or the decoder was used after `finish`.

```manuscript
case InvalidInput
```

### SseError.LimitExceeded

A line or an event exceeds a supplied byte budget.

```manuscript
case LimitExceeded
```

### SseError.ReadFailed

The underlying stream failed to read; the cause keeps its original I/O case.

```manuscript
case ReadFailed(cause: IoError)
```

### SseError.Truncated

The stream ended inside a line or before the blank line that completes an event.

```manuscript
case Truncated
```

### SseError.ReadFailed.cause

The error returned by the borrowed stream.

```manuscript
cause: IoError
```

### SseError.Error.message

Returns a fixed diagnostic that does not echo stream contents.

```manuscript
fn message() -> String:
```

## SseEvent {data-api-kind="Record"}

One dispatched event, with the `message` type used when no `event:` field was sent.

```manuscript
type SseEvent:
    event: String
    data: String
    id: Optional[String]
```

### SseEvent.data

Every `data:` line of the event joined with LF; a bare `data:` line gives an empty line.

```manuscript
data: String
```

### SseEvent.event

The event type from the last `event:` field, or `message`.

```manuscript
event: String
```

### SseEvent.id

The last event ID in effect when the event was dispatched, or none if the stream never set one.

```manuscript
id: Optional[String]
```

## SseLimits {data-api-kind="Record"}

Optional byte budgets for one line and for one event.

```manuscript
type SseLimits:
    max_line_bytes: Optional[Int] = none
    max_event_bytes: Optional[Int] = none
```

### SseLimits.max_event_bytes

Largest total of all field lines in one event, excluding line endings and comments; none adds no budget.

```manuscript
max_event_bytes: Optional[Int] = none
```

### SseLimits.max_line_bytes

Largest line in bytes, excluding its line ending; none adds no budget.

```manuscript
max_line_bytes: Optional[Int] = none
```

## SseReader {data-api-kind="Record"}

Pulls events from a borrowed ReadStream. The reader never closes the stream:
its owner closes it, and closing it makes a blocked read fail with ReadFailed.

```manuscript
type SseReader:
    input: ReadStream
    decoder: SseDecoder
    ready: List[SseEvent]
    next: Int
    chunk_bytes: Optional[Int]
    finished: Bool
```

### SseReader.chunk_bytes

Internal: requested read size, none for the stream default.

```manuscript
chunk_bytes: Optional[Int]
```

### SseReader.decoder

The decoder, whose `retry` is readable between events.

```manuscript
decoder: SseDecoder
```

### SseReader.finished

Internal: true after a clean end of stream.

```manuscript
finished: Bool
```

### SseReader.input

The borrowed stream, such as an HTTP response body.

```manuscript
input: ReadStream
```

### SseReader.next

Internal: index of the next ready event.

```manuscript
next: Int
```

### SseReader.ready

Internal: events decoded but not yet returned.

```manuscript
ready: List[SseEvent]
```

## borrow_body {data-api-kind="Function"}

Views an HTTP response body as a ReadStream that the response keeps owning.
Closing the view does nothing, so close the body itself, usually with `with`.

```manuscript
fn borrow_body(body: ResponseBody) -> ReadStream:
```

## decoder {data-api-kind="Function"}

Creates a decoder. Supplied limits must be positive.

```manuscript
fn decoder(limits: SseLimits = SseLimits()) -> Result[SseDecoder, SseError]:
```

## feed {data-api-kind="Function"}

Decodes one chunk and returns the events it completed, in order.
Chunks may split any line, line ending or UTF-8 scalar. An error is final for the decoder.

```manuscript
fn feed(decoder: SseDecoder, chunk: Bytes) -> Result[List[SseEvent], SseError]:
```

## finish {data-api-kind="Function"}

Ends the stream. A stream with no partial line and no unfinished event ends cleanly;
otherwise the result is Truncated and the unfinished event is never dispatched.

```manuscript
fn finish(decoder: SseDecoder) -> Result[Unit, SseError]:
```

## next_event {data-api-kind="Function"}

Returns the next event, or none after a clean end of stream.
A read failure, malformed line, exceeded limit or truncated event is an error.

```manuscript
fn next_event(reader: SseReader) -> Result[Optional[SseEvent], SseError]:
```

## reader {data-api-kind="Function"}

Wraps a stream in an event reader. Supplied limits and chunk size must be positive.

```manuscript
fn reader(input: ReadStream, limits: SseLimits = SseLimits(), chunk_bytes: Optional[Int] = none) -> Result[SseReader, SseError]:
```

