import {expect_equal, expect_false, expect_ok, expect_true, fail} from "@std/testing.ms"
import range from "@std/collections.ms"
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
    for index in range(0, size):
        single.append(source.slice(index, index + 1).unwrap())
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

fn expect(source: String, want: String) -> Result[Unit, Error]:
    for parts in splits(source.to_bytes()):
        let events = (decode(parts) | try expect_ok)
        let got = summary(events)
        if got != want: return fail(
            "{source.to_bytes().values()}: want {want}, got {got}"
        )

    return ok(unit)

test "LF CRLF and CR endings decode identically under every chunk split":
    let want = "message|a|-;message|b|-"
    (try expect(source: "data: a\n\ndata: b\n\n", want: want))
    (try expect(source: "data: a\r\n\r\ndata: b\r\n\r\n", want: want))
    (try expect(source: "data: a\r\rdata: b\r\r", want: want))
    (try expect(source: "data: a\r\n\ndata: b\n\r\n", want: want))
    (try expect(source: "data: a\n\rdata: b\r\r", want: "message|a|-;message|b|-"))

test "CR LF straddling a chunk boundary is one ending":
    let created = (decoder() | try expect_ok)
    let first = (feed(decoder: created, chunk: "data: a\r".to_bytes()) | try expect_ok)
    let second = (feed(decoder: created, chunk: "\n\r\n".to_bytes()) | try expect_ok)
    (first.length() != 0 or second.length() != 1) | try expect_false

test "repeated data lines join with LF and bare data is an empty line":
    (
        try expect(
            source: "data: a\ndata: b\ndata\ndata:\n\n",
            want: "message|a\nb\n\n|-"
        )
    )
    (try expect(source: "data\n\n", want: "message||-"))

test "comments, unknown fields and a single leading space are handled":
    (
        try expect(
            source: ": ping\ndata:  x\nignored: y\nnocolon\n: another\n\n",
            want: "message| x|-"
        )
    )
    (try expect(source: "data:x:y\n\n", want: "message|x:y|-"))

test "event type applies to one event and id persists":
    (
        try expect(
            source: "event: tick\nid: 7\ndata: 1\n\ndata: 2\n\nid\ndata: 3\n\n",
            want: "tick|1|7;message|2|7;message|3|"
        )
    )

test "ids containing NUL are ignored":
    (
        try expect(
            source: "id: 1\ndata: a\n\nid: x\u{0}y\ndata: b\n\n",
            want: "message|a|1;message|b|1"
        )
    )

test "events without data are not dispatched and reset the event type":
    (try expect(source: "event: lost\n\ndata: a\n\n", want: "message|a|-"))
    (try expect(source: ": only comments\n\n\n", want: ""))

test "retry accepts digits only and survives between events":
    let created = (decoder() | try expect_ok)
    let checked_141 = (
        feed(
            decoder: created,
            chunk: "retry: 1500\n\n".to_bytes()
        ) | try expect_ok
    )
    created.retry.unwrap_or(0) | try expect_equal(expected: 1500)
    let checked_144 = (
        feed(
            decoder: created,
            chunk: "retry: 12x\nretry: -5\nretry:\nretry: 99999999999999999999\n\n".to_bytes()
        ) | try expect_ok
    )
    created.retry.unwrap_or(0) | try expect_equal(expected: 1500)

test "a byte order mark is dropped only at the start of the stream":
    (try expect(source: "\u{feff}data: a\n\n", want: "message|a|-"))
    (try expect(source: "data: a\n\n\u{feff}data: b\n\n", want: "message|a|-"))

test "multi-byte scalars survive every chunk split":
    (try expect(source: "data: é\u{20ac}😀\nevent: 世界\n\n", want: "世界|é\u{20ac}😀|-"))

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
        let created = (decoder() | try expect_ok)
        var failure = false

        for part in parts:
            let outcome = feed(decoder: created, chunk: part)
            if outcome.is_error():
                failure = outcome.unwrap_error() == SseError.InvalidData

        (failure) | try expect_true
        try expect_false(
            not is_case(
                feed(decoder: created, chunk: "data: x\n\n".to_bytes()),
                SseError.InvalidData
            )
        )

test "line and event budgets report LimitExceeded":
    let tight = (decoder(limits: SseLimits(max_line_bytes: some(7))) | try expect_ok)
    try expect_false(
        not is_case(
            feed(decoder: tight, chunk: "data: 12\n\n".to_bytes()),
            SseError.LimitExceeded
        )
    )
    let exact = (decoder(limits: SseLimits(max_line_bytes: some(8))) | try expect_ok)
    (feed(decoder: exact, chunk: "data: 12\n\n".to_bytes()) | try expect_ok).length() | try expect_equal(
        expected: 1
    )
    let event = (decoder(limits: SseLimits(max_event_bytes: some(10))) | try expect_ok)
    let checked_208 = (
        feed(decoder: event, chunk: "data: 1\n".to_bytes()) | try expect_ok
    )
    try expect_false(
        not is_case(
            feed(decoder: event, chunk: "data: 2\n".to_bytes()),
            SseError.LimitExceeded
        )
    )
    let comments = (
        decoder(limits: SseLimits(max_event_bytes: some(10))) | try expect_ok
    )
    let checked_219 = (
        feed(
            decoder: comments,
            chunk: ": a long comment is not counted\ndata: 1\n\n".to_bytes()
        ) | try expect_ok
    )
    decoder(limits: SseLimits(max_line_bytes: some(0))).is_ok() | try expect_false

test "truncated streams fail and clean ends succeed":
    for source in ["data: a\n", "data: a", "data: a\n\ndata", "id: 1\n"]:
        let created = (decoder() | try expect_ok)
        let checked_231 = (
            feed(decoder: created, chunk: source.to_bytes()) | try expect_ok
        )
        let ending = finish(created)
        if ending.is_ok() or ending.unwrap_error() != SseError.Truncated: return fail(
            "{source} must be Truncated"
        )

    for source in ["", "data: a\n\n", ": keepalive\n", "data: a\r\n\r\n", "\n"]:
        let created = (decoder() | try expect_ok)
        let checked_239 = (
            feed(decoder: created, chunk: source.to_bytes()) | try expect_ok
        )
        let clean_end = (finish(created) | try expect_ok)

    let done = (decoder() | try expect_ok)
    let clean_end = (finish(done) | try expect_ok)
    try expect_false(
        not is_case(
            feed(decoder: done, chunk: "x".to_bytes()),
            SseError.InvalidInput
        )
    )

test "reader decodes a borrowed stream and leaves it open":
    let source = stream(
        parts: [
            "data: he".to_bytes(),
            "llo\r".to_bytes(),
            "\n\r\ndata: 2\n\n".to_bytes()
        ],
        failure: none
    )
    let events = (reader(input: ReadStream(value: source)) | try expect_ok)
    let first = (next_event(events) | try expect_ok).unwrap()
    let second = (next_event(events) | try expect_ok).unwrap()
    (first.data != "hello" or second.data != "2") | try expect_false
    (next_event(events) | try expect_ok).is_some() | try expect_false
    (next_event(events) | try expect_ok).is_some() | try expect_false
    source.closed | try expect_false

test "reader reports truncation limits and read failures":
    let cut = (
        reader(
            input: ReadStream(
                value: stream(
                    parts: ["data: a\n".to_bytes()],
                    failure: none
                )
            )
        ) | try expect_ok
    )
    let truncated = next_event(cut)
    (truncated.is_ok() or truncated.unwrap_error() != SseError.Truncated) | try expect_false
    let big = (
        reader(
            input: ReadStream(
                value: stream(
                    parts: ["data: abcdef\n\n".to_bytes()],
                    failure: none
                )
            ),
            limits: SseLimits(max_line_bytes: some(4))
        ) | try expect_ok
    )
    let limited = next_event(big)
    (limited.is_ok() or limited.unwrap_error() != SseError.LimitExceeded) | try expect_false
    let broken = (
        reader(
            input: ReadStream(
                value: stream(
                    parts: ["data: a\n\n".to_bytes()],
                    failure: some(IoError.Closed)
                )
            )
        ) | try expect_ok
    )
    let checked_314 = (next_event(broken) | try expect_ok)
    let failed = next_event(broken)
    failed.is_ok() | try expect_false
    failed.unwrap_error() | try expect_equal(
        expected: SseError.ReadFailed(cause: IoError.Closed)
    )
    reader(
        input: ReadStream(value: stream(parts: [], failure: none)),
        chunk_bytes: some(0)
    ).is_ok() | try expect_false
