// Server-Sent Events decoder implemented in Manuscript.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	ReadStream, Transform, through from "@std/io/io.ms",
)

// One dispatched event, with the `message` type used when no `event:` field was sent.
export type SseEvent:
	// The event type from the last `event:` field, or `message`.
	event: String
	// Every `data:` line of the event joined with LF; a bare `data:` line gives an empty line.
	data: String
	// The last event ID in effect when the event was dispatched, or none if the stream never set one.
	id: String?
	// The latest valid `retry:` reconnection time in milliseconds sent up to this event, or none if the stream sent none.
	retry: Int?

// Optional byte budgets for one line and for one event.
export type SseLimits:
	// Largest line in bytes, excluding its line ending; none adds no budget.
	max_line_bytes: Int?
	// Largest total of all field lines in one event, excluding line endings and comments; none adds no budget.
	max_event_bytes: Int?

// Internal transform state behind `sse_events`.
type Decoder:
	// Limits fixed when the decoder was created.
	limits: SseLimits
	// The latest valid `retry:` value in milliseconds, or none if the stream sent none.
	retry_ms: Int?
	// Internal: the last event ID, which persists across events.
	last_id: String?
	// Internal: bytes of the line being assembled.
	line: BytesBuilder
	// Internal: length of the line being assembled.
	line_bytes: Int
	// Internal: bytes counted against the event budget.
	event_bytes: Int
	// Internal: True when the previous byte was CR, so an immediately following LF is part of the same ending.
	carriage: Bool
	// Internal: True once the first line has been assembled and the byte order mark has been considered.
	started: Bool
	// Internal: True while field lines have arrived since the last blank line.
	open_block: Bool
	// Internal: the pending `event:` value, empty when unset.
	event_type: String
	// Internal: the pending `data:` lines.
	data: List[String]
	// Internal: the first failure, repeated by later calls.
	failure: Error?
	// Internal: True after `finish`.
	closed: Bool

impl Transform[Bytes, SseEvent] for Decoder:
	var fn step(value: Bytes, var out: List[SseEvent]) Unit!:
		var events = List[SseEvent]()
		if failure := self.failure: return error(failure.clone())
		if self.closed: return error(Error("SSE invalid input", kind: "EINVAL"))

		chunk := value
		total := chunk.length()
		var start = 0
		var lf = chunk.index_of_byte(10, 0).get(total)
		var cr = chunk.index_of_byte(13, 0).get(total)

		while start < total:
			var end = lf
			if cr < end: end = cr
			if end == total: break

			byte := chunk.get(end)

			if byte == 10 and self.carriage and end == start:
				self.carriage = false
			else:
				step := complete(var self, chunk, start, end, var events)
				self.carriage = byte == 13

				if step.is_error():
					failure := step.err().clone()
					self.failure = failure.clone()
					return error(failure)

			start = end + 1
			if lf < start: lf = chunk.index_of_byte(10, start).get(total)
			if cr < start: cr = chunk.index_of_byte(13, start).get(total)

		if start < total:
			self.carriage = false

			step := self.hold(chunk.slice(start, total).get())

			if step.is_error():
				failure := step.err().clone()
				self.failure = failure.clone()
				return error(failure)

		for event in events: out.append(event)

	var fn finish(var out: List[SseEvent]) Unit!:
		if failure := self.failure: return error(failure.clone())
		if self.closed: return error(Error("SSE invalid input", kind: "EINVAL"))

		self.closed = true

		if self.line_bytes > 0 or self.open_block:
			self.failure = Error("SSE stream ended inside an event", kind: "EBADMSG")
			return error(Error("SSE stream ended inside an event", kind: "EBADMSG"))

impl Decoder:
	// Buffers the unterminated tail of a chunk as part of the line being assembled.
	var fn hold(segment: Bytes) Unit!:
		self.line_bytes += segment.length()
		if exceeds(self.line_bytes, self.limits.max_line_bytes): return error(
			Error("SSE limit exceeded", kind: "EOVERFLOW")
		)

		self.line.append_bytes(segment)

	var fn apply(line: String) Unit:
		if line.starts_with("data:"):
			self.data.append(value_after(line, 5, line.starts_with("data: ")))
		else if line.starts_with("event:"):
			self.event_type = value_after(line, 6, line.starts_with("event: "))
		else if line.starts_with("id:"):
			self.identify(value_after(line, 3, line.starts_with("id: ")))
		else if line.starts_with("retry:"):
			self.reconnect(value_after(line, 6, line.starts_with("retry: ")))
		else: self.apply_other(line)

	// Lines without a colon name a field with an empty value; other names are ignored.
	var fn apply_other(line: String) Unit:
		if line.index_of(":").is_some(): return unit

		if line == "data": self.data.append("")
		else if line == "event": self.event_type = ""
		else if line == "id": self.identify("")
		else if line == "retry": self.reconnect("")

	// An ID containing NUL is ignored, so it neither replaces nor clears the last ID.
	var fn identify(value: String) Unit:
		if value.to_bytes().contains("\u{0}".to_bytes()): return unit

		self.last_id = value

	// Only ASCII digits form a retry time; overflow and signs are ignored.
	var fn reconnect(value: String) Unit:
		if (value.is_empty() or value.starts_with("-") or value.starts_with("+")): return unit

		milliseconds := value.parse_int()
		if milliseconds.is_some(): self.retry_ms = milliseconds

/*
Decodes a Server-Sent Events byte stream into events, in order.

Chunks may split any line, line ending or UTF-8 scalar. A stream with no partial line and no unfinished
event ends cleanly; otherwise the final read fails with `EBADMSG` and the unfinished event is never
dispatched. A malformed line or an exceeded limit fails the read, and the failure is final. Supplied limits
must be positive, otherwise the first read fails with `EINVAL`. Closing the result closes `input`.
*/
// ms: effect std.net.connect
export fn sse_events(
	input: ReadStream[Bytes],
	limits: SseLimits = SseLimits()
) ReadStream[SseEvent]:
	var failure: Error? = none
	if not positive(limits.max_line_bytes) or not positive(limits.max_event_bytes):
		failure = Error("SSE invalid input", kind: "EINVAL")
	return through[Bytes, SseEvent](
		input,
		Decoder(
			limits: limits, retry_ms: none, last_id: none, line: BytesBuilder(),
			line_bytes: 0, event_bytes: 0, carriage: false, started: false,
			open_block: false, event_type: "", data: List[String](), failure: failure,
			closed: false
		)
	)

fn positive(limit: Int?) Bool:
	if maximum := limit: return maximum > 0
	return true

fn exceeds(value: Int, limit: Int?) Bool:
	if maximum := limit: return value > maximum
	return false

// Finishes the line `chunk[start, end)` that ends at a terminator, joining it with any bytes held from earlier chunks.
fn complete(
	var decoder: Decoder, chunk: Bytes, start: Int, end: Int, var events: List[SseEvent]
) Unit!:
	if decoder.line_bytes == 0:
		if exceeds(end - start, decoder.limits.max_line_bytes): return error(
			Error("SSE limit exceeded", kind: "EOVERFLOW")
		)
		return end_line(var decoder, chunk, start, end, var events)

	try decoder.hold(chunk.slice(start, end).get())

	joined := decoder.line.drain()
	decoder.line_bytes = 0
	return end_line(var decoder, joined, 0, joined.length(), var events)

fn end_line(
	var decoder: Decoder, bytes: Bytes, start: Int, end: Int, var events: List[SseEvent]
) Unit!:
	var from = start

	if not decoder.started:
		decoder.started = true
		if bytes.slice(start, end).get().starts_with("\u{feff}".to_bytes()): from += 3

	if from == end:
		dispatch(var decoder, var events)
		return ok(unit)

	line := try bytes.decode_utf8_range(
		from, end
	).ok_or(Error("SSE line is not valid UTF-8", kind: "EBADMSG"))
	if line.starts_with(":"): return ok(unit)

	decoder.event_bytes += end - from
	if exceeds(decoder.event_bytes, decoder.limits.max_event_bytes): return error(
		Error("SSE limit exceeded", kind: "EOVERFLOW")
	)

	decoder.open_block = true
	decoder.apply(line)
	return ok(unit)

// The value after the colon, skipping one leading space when `spaced`.
fn value_after(line: String, colon_end: Int, spaced: Bool) String:
	if spaced: return line.slice(colon_end + 1, line.length()).get()
	return line.slice(colon_end, line.length()).get()

fn dispatch(var decoder: Decoder, var events: List[SseEvent]) Unit:
	if not decoder.data.is_empty():
		var name = decoder.event_type.clone()
		if name == "": name = "message"
		events.append(
			SseEvent(
				name, decoder.data.join("\n"), decoder.last_id.clone(), decoder.retry_ms
			)
		)

	decoder.event_type = ""
	decoder.data = List[String]()
	decoder.event_bytes = 0
	decoder.open_block = false
