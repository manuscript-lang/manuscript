import (
	expect_equal, expect_false, fail from "@std/test/test.ms",
	Bytes, BytesBuilder from "@std/bytes.ms",
	ReadStream, Source from "@std/io/io.ms",
	sse_events, SseEvent, SseLimits from "@std/net/sse.ms",
)

// Hands out the chunks in order, then fails with `failure` if set, else ends.
type Chunks:
	parts: List[Bytes]
	index: Int
	failure: Error?

impl Source[Bytes] for Chunks:
	var fn next() Bytes?!:
		if self.index < self.parts.length():
			part := self.parts[self.index].clone()
			self.index += 1
			return ok(part)

		if cause := self.failure: return error(cause.clone())

		return ok(none)

	var fn close() Unit!:
		return ok(unit)

fn chunks(parts: List[Bytes]) ReadStream[Bytes]:
	return ReadStream[Bytes](Chunks(parts, 0, none))

// Splits at every byte boundary, one boundary at a time, plus one byte per chunk.
fn splits(source: Bytes) List[List[Bytes]]:
	var all = List[List[Bytes]]()
	size := source.length()
	for cut in 0..size + 1:
		all.append([source.slice(0, cut).get(), source.slice(cut, size).get()])

	var single = List[Bytes]()
	for index in 0..size:
		single.append(source.slice(index, index + 1).get())
	all.append(single)
	return all

// Reads every event, or the first error.
fn decode(parts: List[Bytes], limits: SseLimits = SseLimits()) List[SseEvent]!:
	var events = sse_events(chunks(parts), limits)
	var out = List[SseEvent]()

	while true:
		next := try events.next()

		if event := next:
			out.append(event)
		else:
			break

	return ok(out)

fn summary(events: List[SseEvent]) String:
	return events.map(
		fn event: "{event.event}|{event.data}|{event.id.get("-")}"
	).join(";")

fn expect(source: String, want: String) Unit!:
	for parts in splits(source.to_bytes()):
		got := summary(try decode(parts))
		if got != want: return fail(
			"{source.to_bytes().values()}: want {want}, got {got}"
		)

test "LF CRLF and CR endings decode identically under every chunk split":
	want := "message|a|-;message|b|-"
	try expect("data: a\n\ndata: b\n\n", want)
	try expect("data: a\r\n\r\ndata: b\r\n\r\n", want)
	try expect("data: a\r\rdata: b\r\r", want)
	try expect("data: a\r\n\ndata: b\n\r\n", want)

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

test "events carry the latest valid retry time":
	events := try decode(["retry: 1500\ndata: a\n\n".to_bytes()])
	try expect_equal(events[0].retry, 1500)

	kept := try decode(
		[
			"retry: 1500\ndata: a\n\nretry: 12x\nretry: -5\nretry:\ndata: b\n\n".to_bytes()
		]
	)
	try expect_equal(kept[1].retry, 1500)

	none_sent := try decode(["data: a\n\n".to_bytes()])
	try expect_equal(none_sent[0].retry, none)

test "a byte order mark is dropped only at the start of the stream":
	try expect("\u{feff}data: a\n\n", "message|a|-")
	try expect("data: a\n\n\u{feff}data: b\n\n", "message|a|-")

test "multi-byte scalars survive every chunk split":
	try expect("data: é\u{20ac}😀\nevent: 世界\n\n", "世界|é\u{20ac}😀|-")

test "invalid UTF-8 is InvalidData":
	var builder = BytesBuilder()
	builder.append_bytes("data: ".to_bytes())
	builder.append(255)
	builder.append_bytes("\n\n".to_bytes())

	for parts in splits(builder.build()):
		outcome := decode(parts)
		try expect_false(outcome.is_ok())
		try expect_equal(outcome.err().kind, "EBADMSG")

test "line and event budgets report LimitExceeded":
	tight := decode(["data: 12\n\n".to_bytes()], SseLimits(7))
	try expect_equal(tight.err().kind, "EOVERFLOW")
	try expect_equal(
		(try decode(["data: 12\n\n".to_bytes()], SseLimits(8))).length(), 1
	)

	event := decode(
		["data: 1\n".to_bytes(), "data: 2\n".to_bytes()], SseLimits(max_event_bytes: 10)
	)
	try expect_equal(event.err().kind, "EOVERFLOW")

	comments := decode(
		[": a long comment is not counted\ndata: 1\n\n".to_bytes()],
		SseLimits(max_event_bytes: 10)
	)
	try expect_equal((try comments).length(), 1)

	zero := decode(["data: a\n\n".to_bytes()], SseLimits(0))
	try expect_equal(zero.err().kind, "EINVAL")

test "truncated streams fail and clean ends succeed":
	for source in ["data: a\n", "data: a", "data: a\n\ndata", "id: 1\n"]:
		outcome := decode([source.to_bytes()])
		if outcome.is_ok() or outcome.err().kind != "EBADMSG": return fail(
			"{source} must be truncated"
		)

	for source in ["", "data: a\n\n", ": keepalive\n", "data: a\r\n\r\n", "\n"]:
		_events := try decode([source.to_bytes()])

test "a read failure is the stream's error and events before it arrive":
	var events = sse_events(
		ReadStream[Bytes](
			Chunks(
				["data: a\n\n".to_bytes()], 0, Error("I/O: closed", kind: "EBADF")
			)
		)
	)
	first := (try events.next()).get()
	try expect_equal(first.data, "a")

	failed := events.next()
	try expect_equal(failed.err().kind, "EBADF")
