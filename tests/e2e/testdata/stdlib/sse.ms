import {
    decoder,
    feed,
    finish,
    reader,
    next_event,
    SseDecoder,
    SseError,
    SseEvent,
    SseLimits
} from "@std/sse.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {IoError, ReadStream} from "@std/io.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

type Chunks:
    parts: List[Bytes]
    index: Int
    closed: Bool
    failure: Optional[IoError]

impl ReadStream for Chunks:
    fn close() -> Unit:
        self.closed = true

    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        if self.index < self.parts.length():
            let part = self.parts.at(self.index).unwrap()
            self.index = self.index + 1
            return ok(some(part))

        if self.failure.is_some(): return error(self.failure.unwrap())

        return ok(none)

fn stream(parts: List[Bytes], failure: Optional[IoError]) -> Chunks:
    return Chunks(parts: parts, index: 0, closed: false, failure: failure)

# Splits at every byte boundary, one boundary at a time, plus one byte per chunk.
fn splits(source: Bytes) -> List[List[Bytes]]:
    let all = List[List[Bytes]]()
    let size = source.length()
    var cut = 0

    while cut <= size:
        let head = source.slice(0, cut).unwrap()
        let tail = source.slice(cut, size).unwrap()
        all.append([head, tail])
        cut = cut + 1

    let single = List[Bytes]()
    var index = 0

    while index < size:
        single.append(source.slice(index, index + 1).unwrap())
        index = index + 1

    all.append(single)
    return all

fn decode(parts: List[Bytes]) -> Result[List[SseEvent], SseError]:
    let created = try decoder()
    let events = List[SseEvent]()

    for part in parts:
        let batch = try feed(decoder: created, chunk: part)
        for event in batch: events.append(event)

    try finish(decoder: created)
    return ok(events)

fn summary(events: List[SseEvent]) -> String:
    return (
        events
        .map(fn(event): "{event.event}|{event.data}|{event.id.unwrap_or("-")}")
        .join(";")
    )

fn expect(source: String, want: String) -> Unit:
    for parts in splits(source.to_bytes()):
        let events = decode(parts) | value
        let got = summary(events)
        if got != want:
            panic("{source.to_bytes().values()}: want {want}, got {got}")

test "LF CRLF and CR endings decode identically under every chunk split":
    let want = "message|a|-;message|b|-"
    expect(source: "data: a\n\ndata: b\n\n", want: want)
    expect(source: "data: a\r\n\r\ndata: b\r\n\r\n", want: want)
    expect(source: "data: a\r\rdata: b\r\r", want: want)
    expect(source: "data: a\r\n\ndata: b\n\r\n", want: want)
    expect(source: "data: a\n\rdata: b\r\r", want: "message|a|-;message|b|-")

test "CR LF straddling a chunk boundary is one ending":
    let created = decoder() | value
    let first = feed(decoder: created, chunk: "data: a\r".to_bytes()) | value
    let second = feed(decoder: created, chunk: "\n\r\n".to_bytes()) | value
    if first.length() != 0 or second.length() != 1:
        panic("CRLF split across chunks must dispatch exactly once")

test "repeated data lines join with LF and bare data is an empty line":
    expect(source: "data: a\ndata: b\ndata\ndata:\n\n", want: "message|a\nb\n\n|-")
    expect(source: "data\n\n", want: "message||-")

test "comments, unknown fields and a single leading space are handled":
    expect(
        source: ": ping\ndata:  x\nignored: y\nnocolon\n: another\n\n",
        want: "message| x|-"
    )
    expect(source: "data:x:y\n\n", want: "message|x:y|-")

test "event type applies to one event and id persists":
    expect(
        source: "event: tick\nid: 7\ndata: 1\n\ndata: 2\n\nid\ndata: 3\n\n",
        want: "tick|1|7;message|2|7;message|3|"
    )

test "ids containing NUL are ignored":
    expect(
        source: "id: 1\ndata: a\n\nid: x\u{0}y\ndata: b\n\n",
        want: "message|a|1;message|b|1"
    )

test "events without data are not dispatched and reset the event type":
    expect(source: "event: lost\n\ndata: a\n\n", want: "message|a|-")
    expect(source: ": only comments\n\n\n", want: "")

test "retry accepts digits only and survives between events":
    let created = decoder() | value
    feed(decoder: created, chunk: "retry: 1500\n\n".to_bytes()) | value
    if created.retry.unwrap_or(0) != 1500: panic("retry was not recorded")
    feed(
        decoder: created,
        chunk: "retry: 12x\nretry: -5\nretry:\nretry: 99999999999999999999\n\n".to_bytes()
    ) | value
    if created.retry.unwrap_or(0) != 1500: panic("invalid retry values must be ignored")

test "a byte order mark is dropped only at the start of the stream":
    expect(source: "\u{feff}data: a\n\n", want: "message|a|-")
    expect(source: "data: a\n\n\u{feff}data: b\n\n", want: "message|a|-")

test "multi-byte scalars survive every chunk split":
    expect(source: "data: é\u{20ac}😀\nevent: 世界\n\n", want: "世界|é\u{20ac}😀|-")

fn invalid_bytes() -> Bytes:
    let builder = BytesBuilder()
    builder.concat("data: ".to_bytes())
    builder.append(255)
    builder.concat("\n\n".to_bytes())
    return builder.freeze()

fn is_case(result: Result[List[SseEvent], SseError], want: SseError) -> Bool:
    if not result.is_error(): return false

    return result.unwrap_error() == want

test "invalid UTF-8 is InvalidData and final":
    for parts in splits(invalid_bytes()):
        let created = decoder() | value
        var failure = false

        for part in parts:
            let outcome = feed(decoder: created, chunk: part)
            if outcome.is_error():
                failure = outcome.unwrap_error() == SseError.InvalidData

        if not failure: panic("invalid UTF-8 must report InvalidData")
        if not is_case(
            feed(decoder: created, chunk: "data: x\n\n".to_bytes()),
            SseError.InvalidData
        ):
            panic("a failed decoder must keep reporting its failure")

test "line and event budgets report LimitExceeded":
    let tight = decoder(limits: SseLimits(max_line_bytes: some(7))) | value
    if not is_case(
        feed(decoder: tight, chunk: "data: 12\n\n".to_bytes()),
        SseError.LimitExceeded
    ):
        panic("line budget")
    let exact = decoder(limits: SseLimits(max_line_bytes: some(8))) | value
    if value(feed(decoder: exact, chunk: "data: 12\n\n".to_bytes())).length() != 1:
        panic("a line at the budget is accepted")
    let event = decoder(limits: SseLimits(max_event_bytes: some(10))) | value
    feed(decoder: event, chunk: "data: 1\n".to_bytes()) | value
    if not is_case(
        feed(decoder: event, chunk: "data: 2\n".to_bytes()),
        SseError.LimitExceeded
    ):
        panic("event budget")
    let comments = decoder(limits: SseLimits(max_event_bytes: some(10))) | value
    feed(
        decoder: comments,
        chunk: ": a long comment is not counted\ndata: 1\n\n".to_bytes()
    ) | value
    if decoder(limits: SseLimits(max_line_bytes: some(0))).is_ok(): panic(
        "zero line budget"
    )

test "truncated streams fail and clean ends succeed":
    for source in ["data: a\n", "data: a", "data: a\n\ndata", "id: 1\n"]:
        let created = decoder() | value
        feed(decoder: created, chunk: source.to_bytes()) | value
        let ending = finish(created)
        if ending.is_ok() or ending.unwrap_error() != SseError.Truncated:
            panic("{source} must be Truncated")

    for source in ["", "data: a\n\n", ": keepalive\n", "data: a\r\n\r\n", "\n"]:
        let created = decoder() | value
        feed(decoder: created, chunk: source.to_bytes()) | value
        finish(created) | value

    let done = decoder() | value
    finish(done) | value
    if not is_case(feed(decoder: done, chunk: "x".to_bytes()), SseError.InvalidInput):
        panic("feed after finish")

test "reader decodes a borrowed stream and leaves it open":
    let source = stream(
        parts: [
            "data: he".to_bytes(),
            "llo\r".to_bytes(),
            "\n\r\ndata: 2\n\n".to_bytes()
        ],
        failure: none
    )
    let events = reader(input: ReadStream(value: source)) | value
    let first = value(next_event(events)).unwrap()
    let second = value(next_event(events)).unwrap()
    if first.data != "hello" or second.data != "2": panic("reader events")
    if value(next_event(events)).is_some(): panic("clean end of stream")
    if value(next_event(events)).is_some(): panic("end of stream is stable")
    if source.closed: panic("the reader must not close a borrowed stream")

test "reader reports truncation limits and read failures":
    let cut = reader(
        input: ReadStream(
            value: stream(parts: ["data: a\n".to_bytes()], failure: none)
        )
    ) | value
    let truncated = next_event(cut)
    if truncated.is_ok() or truncated.unwrap_error() != SseError.Truncated: panic(
        "truncated"
    )
    let big = reader(
        input: ReadStream(
            value: stream(
                parts: ["data: abcdef\n\n".to_bytes()],
                failure: none
            )
        ),
        limits: SseLimits(max_line_bytes: some(4))
    ) | value
    let limited = next_event(big)
    if limited.is_ok() or limited.unwrap_error() != SseError.LimitExceeded: panic(
        "limit"
    )
    let broken = reader(
        input: ReadStream(
            value: stream(
                parts: ["data: a\n\n".to_bytes()],
                failure: some(IoError.Closed)
            )
        )
    ) | value
    next_event(broken) | value
    let failed = next_event(broken)
    if failed.is_ok(): panic("read failure")
    if failed.unwrap_error() != SseError.ReadFailed(cause: IoError.Closed):
        panic("read failure keeps its IoError identity")
    if reader(
        input: ReadStream(value: stream(parts: [], failure: none)),
        chunk_bytes: some(0)
    ).is_ok():
        panic("zero chunk size")
