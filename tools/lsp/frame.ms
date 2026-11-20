// Framed JSON-RPC input and output for the language server: `Content-Length` headers,
// a blank line, then the body. The rules follow crates/ms-lsp/src/transport.rs: headers
// stop at 8192 bytes, a body at 16 MiB, `Content-Length` appears once, and a line
// without a colon is a protocol failure.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

MAX_HEADER := 8192
MAX_BODY := 16777216

// Bytes read so far and not yet returned as a frame.
export type Framer:
	buffer: Bytes = "".to_bytes()

// Where the blank line that ends the headers starts, and how many bytes it takes.
type HeaderEnd:
	at: Int
	width: Int

fn header_end(buffer: Bytes) HeaderEnd?:
	crlf := buffer.index_of("\r\n\r\n".to_bytes())
	lf := buffer.index_of("\n\n".to_bytes())

	if crlf_at := crlf:
		if lf_at := lf:
			if lf_at < crlf_at: return HeaderEnd(at: lf_at, width: 2)
		return HeaderEnd(at: crlf_at, width: 4)

	if lf_at := lf: return HeaderEnd(at: lf_at, width: 2)

	return none

fn failed(message: String) Error: Error(message)

// The value of the one `Content-Length` header in `headers`.
fn content_length(headers: String) Int!:
	var length: Int? = none

	for raw in headers.split("\n"):
		line := raw.trim()
		if line.is_empty(): continue

		parts := line.split_once(":")
		if parts.is_none(): return error(failed("malformed protocol header"))
		if parts.get().before.trim().lower() != "content-length": continue
		if length.is_some(): return error(failed("duplicate Content-Length"))

		parsed := parts.get().after.trim().parse_int()
		if parsed.is_none(): return error(failed("invalid Content-Length"))

		length = parsed

	size := length.ok_or(failed("invalid Content-Length"))?
	if size < 0 or size > MAX_BODY: return error(failed("invalid Content-Length"))

	return ok(size)

// Appends bytes read from the client.
fn var Framer.push(data: Bytes) Void:
	self.buffer = self.buffer.concat(data)

// Takes the next whole frame's body, or `none` while more bytes are needed. A header
// that is too long or malformed, or a bad length, is an error and ends the session.
fn var Framer.next_frame() Bytes?!:
	end := header_end(self.buffer)

	if end.is_none():
		if self.buffer.length() > MAX_HEADER: return error(
			failed("protocol header exceeds 8192 bytes")
		)
		return ok(none)

	found := end.get()
	if found.at + found.width > MAX_HEADER: return error(
		failed("protocol header exceeds 8192 bytes")
	)

	headers := self.buffer.decode_utf8_range(0, found.at).get_or("")
	size := content_length(headers)?
	start := found.at + found.width
	if self.buffer.length() < start + size: return ok(none)

	body := self.buffer.slice(start, start + size)?
	self.buffer = self.buffer.slice(start + size, self.buffer.length())?
	return ok(body)

// The bytes that carry `body` to the client.
export fn encode(body: String) Bytes:
	payload := body.to_bytes()
	return f"Content-Length: {payload.length()}\r\n\r\n".to_bytes().concat(payload)

test "a frame is read once its body has arrived":
	var framer = Framer()
	framer.push("Content-Length: 2\r\n\r\n{".to_bytes())
	expect_equal(framer.next_frame()?.is_none(), true)?
	framer.push("}Content-Length: 1\r\n\r\nx".to_bytes())
	expect_equal(framer.next_frame()?.get().decode_utf8().get(), "{}")?
	expect_equal(framer.next_frame()?.get().decode_utf8().get(), "x")?
	expect_equal(framer.next_frame()?.is_none(), true)?

test "header names ignore case and extra headers are skipped":
	var framer = Framer()
	framer.push("content-length:2\r\nX: y\r\n\r\n{}".to_bytes())
	expect_equal(framer.next_frame()?.get().decode_utf8().get(), "{}")?

test "bad frames are protocol failures":
	for bad in [
		"Content-Length: -1\r\n\r\n", "Content-Length: 999999999\r\n\r\n",
		"Content-Length: 1\r\nContent-Length: 1\r\n\r\nx", "NoColon\r\n\r\n", "\r\n\r\n"
	]:
		var framer = Framer()
		framer.push(bad.to_bytes())
		expect_equal(framer.next_frame().is_error(), true)?

test "an oversized header is refused before its end arrives":
	var framer = Framer()
	framer.push("Content-Length: 1\r\nX: ".to_bytes())
	framer.push("a".repeat(9000).to_bytes())
	expect_equal(framer.next_frame().is_error(), true)?

test "encode prefixes the byte length":
	expect_equal(encode("é").decode_utf8().get(), "Content-Length: 2\r\n\r\né")?
