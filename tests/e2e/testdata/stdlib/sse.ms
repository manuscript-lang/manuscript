import {expect_equal, expect_false, fail} from "@std/testing.ms"
import range from "@std/collections.ms"
import {decoder, reader, next_event, SseError, SseEvent, SseLimits} from "@std/sse.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {IoError, ReadStream} from "@std/io.ms"

type Chunks:
    parts: List[Bytes]
    index: Int
    closed: Bool
    failure: Optional[IoError]

impl ReadStream for Chunks:
    fn close() Unit:
        self.closed = true

    fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]:
        if self.index < self.parts.length():
            let part = self.parts.at(self.index).get()
            self.index += 1
            return ok(some(part))

        if let cause = self.failure: return error(cause)

        return ok(none)

fn stream(parts: List[Bytes], failure: Optional[IoError]) Chunks:
    return Chunks(parts, 0, closed: false, failure)

# Splits at every byte boundary, one boundary at a time, plus one byte per chunk.
fn splits(source: Bytes) List[List[Bytes]]:
    let all = List[List[Bytes]]()
    let size = source.length()

    for cut in range(0, size + 1):
        let head = source.slice(0, cut).get()
        let tail = source.slice(cut, size).get()
        all.append([head, tail])

    let single = List[Bytes]()
    for index in range(0, size):
        single.append(source.slice(index, index + 1).get())
    all.append(single)
    return all

fn decode(parts: List[Bytes]) Result[List[SseEvent], SseError]:
    let created = try decoder()
    let events = List[SseEvent]()

    for part in parts:
        let batch = try created.feed(part)
        for event in batch: events.append(event)

    try created.finish()
    return ok(events)

fn summary(events: List[SseEvent]) String:
    return (
        events
        .map(fn(event): "{event.event}|{event.data}|{event.id.get("-")}")
        .join(";")
    )

fn expect(source: String, want: String) Result[Unit, Error]:
    for parts in splits(source.to_bytes()):
        let events = try decode(parts)
        let got = summary(events)
        if got != want: return fail(
            "{source.to_bytes().values()}: want {want}, got {got}"
        )

    return ok(unit)

test "LF CRLF and CR endings decode identically under every chunk split":
    let want = "message|a|-;message|b|-"
    try expect("data: a\n\ndata: b\n\n", want)
    try expect("data: a\r\n\r\ndata: b\r\n\r\n", want)
    try expect("data: a\r\rdata: b\r\r", want)
    try expect("data: a\r\n\ndata: b\n\r\n", want)
    try expect("data: a\n\rdata: b\r\r", "message|a|-;message|b|-")

test "CR LF straddling a chunk boundary is one ending":
    let created = try decoder()
    let first = try created.feed("data: a\r".to_bytes())
    let second = try created.feed("\n\r\n".to_bytes())
    try expect_false(first.length() != 0 or second.length() != 1)

test "repeated data lines join with LF and bare data is an empty line":
    try expect("data: a\ndata: b\ndata\ndata:\n\n", "message|a\nb\n\n|-")
    try expect("data\n\n", "message||-")

test "comments, unknown fields and a single leading space are handled":
    try expect(": ping\ndata:  x\nignored: y\nnocolon\n: another\n\n", "message| x|-")
    try expect("data:x:y\n\n", "message|x:y|-")

test "event type applies to one event and id persists":
    try expect(
        "event: tick\nid: 7\ndata: 1\n\ndata: 2\n\nid\ndata: 3\n\n",
        "tick|1|7;message|2|7;message|3|"
    )

test "ids containing NUL are ignored":
    try expect("id: 1\ndata: a\n\nid: x\u{0}y\ndata: b\n\n", "message|a|1;message|b|1")

test "events without data are not dispatched and reset the event type":
    try expect("event: lost\n\ndata: a\n\n", "message|a|-")
    try expect(": only comments\n\n\n", "")

test "retry accepts digits only and survives between events":
    let created = try decoder()
    let _events = try created.feed("retry: 1500\n\n".to_bytes())
    try expect_equal(created.retry().get(0), 1500)
    let _second_events = try created.feed(
        "retry: 12x\nretry: -5\nretry:\nretry: 99999999999999999999\n\n".to_bytes()
    )
    try expect_equal(created.retry().get(0), 1500)

test "a byte order mark is dropped only at the start of the stream":
    try expect("\u{feff}data: a\n\n", "message|a|-")
    try expect("data: a\n\n\u{feff}data: b\n\n", "message|a|-")

test "multi-byte scalars survive every chunk split":
    try expect("data: é\u{20ac}😀\nevent: 世界\n\n", "世界|é\u{20ac}😀|-")

fn invalid_bytes() Bytes:
    let builder = BytesBuilder()
    builder.concat("data: ".to_bytes())
    builder.append(255)
    builder.concat("\n\n".to_bytes())
    return builder.freeze()

fn is_case(result: Result[List[SseEvent], SseError], want: SseError) Bool:
    if not result.is_error(): return false

    return result.err() == want

test "invalid UTF-8 is InvalidData and final":
    for parts in splits(invalid_bytes()):
        let created = try decoder()
        var failure = false

        for part in parts:
            let outcome = created.feed(part)
            if outcome.is_error():
                failure = outcome.err() == SseError.InvalidData

        try expect_false(not failure)
        try expect_false(
            not is_case(
                created.feed("data: x\n\n".to_bytes()),
                SseError.InvalidData
            )
        )

test "line and event budgets report LimitExceeded":
    let tight = try decoder(SseLimits(some(7)))
    try expect_false(
        not is_case(
            tight.feed("data: 12\n\n".to_bytes()),
            SseError.LimitExceeded
        )
    )
    let exact = try decoder(SseLimits(some(8)))
    try expect_equal((try exact.feed("data: 12\n\n".to_bytes())).length(), 1)
    let event = try decoder(SseLimits(max_event_bytes: some(10)))
    let _event_batch = try event.feed("data: 1\n".to_bytes())
    try expect_false(
        not is_case(event.feed("data: 2\n".to_bytes()), SseError.LimitExceeded)
    )
    let comments = try decoder(SseLimits(max_event_bytes: some(10)))
    let _comment_events = try comments.feed(
        ": a long comment is not counted\ndata: 1\n\n".to_bytes()
    )
    try expect_false(decoder(SseLimits(some(0))).is_ok())

test "truncated streams fail and clean ends succeed":
    for source in ["data: a\n", "data: a", "data: a\n\ndata", "id: 1\n"]:
        let created = try decoder()
        let _events = try created.feed(source.to_bytes())
        let ending = created.finish()
        if ending.is_ok() or ending.err() != SseError.Truncated: return fail(
            "{source} must be Truncated"
        )

    for source in ["", "data: a\n\n", ": keepalive\n", "data: a\r\n\r\n", "\n"]:
        let created = try decoder()
        let _events = try created.feed(source.to_bytes())
        try created.finish()

    let done = try decoder()
    try done.finish()
    try expect_false(not is_case(done.feed("x".to_bytes()), SseError.InvalidInput))

test "reader decodes a borrowed stream and leaves it open":
    let source = stream(
        [
            "data: he".to_bytes(),
            "llo\r".to_bytes(),
            "\n\r\ndata: 2\n\n".to_bytes()
        ],
        none
    )
    let events = try reader(ReadStream(source))
    let first = (try next_event(events)).get()
    let second = (try next_event(events)).get()
    try expect_false(first.data != "hello" or second.data != "2")
    try expect_false((try next_event(events)).is_some())
    try expect_false((try next_event(events)).is_some())
    try expect_false(source.closed)

test "reader reports truncation limits and read failures":
    let cut = try reader(ReadStream(stream(["data: a\n".to_bytes()], none)))
    let truncated = next_event(cut)
    try expect_false(truncated.is_ok() or truncated.err() != SseError.Truncated)
    let big = try reader(
        ReadStream(stream(["data: abcdef\n\n".to_bytes()], none)),
        SseLimits(some(4))
    )
    let limited = next_event(big)
    try expect_false(limited.is_ok() or limited.err() != SseError.LimitExceeded)
    let broken = try reader(
        ReadStream(
            value: stream(["data: a\n\n".to_bytes()], some(IoError.Closed))
        )
    )
    let _event = try next_event(broken)
    let failed = next_event(broken)
    try expect_false(failed.is_ok())
    try expect_equal(failed.err(), SseError.ReadFailed(IoError.Closed))
    try expect_false(reader(ReadStream(stream([], none)), chunk_bytes: some(0)).is_ok())
