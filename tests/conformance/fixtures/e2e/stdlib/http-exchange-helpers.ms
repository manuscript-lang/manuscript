// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	HttpExchange,
	HttpHeaders,
	HttpMethod,
	HttpRequest,
	HttpResponse,
	buffered,
	headers,
	read_body,
	reply,
	text from "@std/net/http.ms",
	WebSocket from "@std/net/websocket.ms",
	expect_equal from "@std/test/test.ms",
)

// An exchange that serves scripted request chunks and accepts exactly one response: its
// `send` fails unless the status and body are the ones `expect_status` and `expect_body`
// name, so a helper that sent anything else shows as an error.
type Scripted:
	verb: HttpMethod
	target: String
	query_text: String
	chunks: List[Bytes]
	expect_status: Int
	expect_body: String
	next_chunk: Int = 0

fn var Scripted.close() Void:
	return

fn Scripted.headers() HttpHeaders:
	return headers()

fn Scripted.method() HttpMethod:
	return self.verb.clone()

fn Scripted.path() String:
	return self.target.clone()

fn Scripted.protocol() String:
	return "HTTP/1.1"

fn Scripted.query() String:
	return self.query_text.clone()

fn var Scripted.read(max_bytes: Int?) Bytes?!:
	if self.next_chunk >= self.chunks.length(): return ok(none)

	chunk := self.chunks.get(self.next_chunk).clone()
	self.next_chunk += 1
	return ok(chunk)

fn var Scripted.send(status: Int, headers: HttpHeaders, body: Bytes) Void!:
	if status != self.expect_status: return error(
		Error(f"sent status {status}", kind: "EINVAL")
	)

	got := body.decode_utf8().get_or("")
	if got != self.expect_body: return error(Error(f"sent body {got}", kind: "EINVAL"))

	return ok()

fn var Scripted.send_headers(status: Int, headers: HttpHeaders) Void!:
	return error(Error("unexpected send_headers", kind: "EINVAL"))

fn var Scripted.write(move data: String) Void!:
	return error(Error("unexpected write", kind: "EINVAL"))

fn var Scripted.write_bytes(move data: Bytes) Void!:
	return error(Error("unexpected write_bytes", kind: "EINVAL"))

fn var Scripted.upgrade(
	allowed_origins: List[String] = [],
	subprotocols: List[String] = [],
	max_message_bytes: Int? = none,
) WebSocket!:
	return error(Error("unexpected upgrade", kind: "EINVAL"))

fn scripted(chunks: List[Bytes], status: Int, body: String) Scripted:
	return Scripted(
		verb: HttpMethod.Post,
		target: "/x",
		query_text: "",
		chunks: chunks,
		expect_status: status,
		expect_body: body,
	)

fn echo(request: HttpRequest) HttpResponse:
	return text(201, f"{request.path}:{request.body.decode_utf8().get_or("")}")

test "buffered adapts a request-to-response handler":
	var exchange: HttpExchange = scripted(
		["a".to_bytes(), "bc".to_bytes()],
		201,
		"/x:abc",
	)
	handler := buffered(echo)
	handler(exchange)?

test "a buffered handler sees the exchange's method, path and query":
	var exchange: HttpExchange = Scripted(
		verb: HttpMethod.Put,
		target: "/items",
		query_text: "id=7",
		chunks: [],
		expect_status: 200,
		expect_body: "PUT /items?id=7",
	)
	describe := fn(request: HttpRequest) HttpResponse:
		return text(200, f"{request.method.to_string()} {request.path}?{request.query}")
	buffered(describe)(exchange)?

test "read_body bounds the body by its limit":
	var small: HttpExchange = scripted(["12345".to_bytes()], 200, "")
	body := read_body(small, 8)?
	expect_equal(body.length(), 5)?

	var large: HttpExchange = scripted(["1234".to_bytes(), "56789".to_bytes()], 200, "")
	failed := read_body(large, 8)
	expect_equal(failed.is_error(), true)?
	expect_equal(failed.err().kind, "EOVERFLOW")?

test "read_body joins every chunk and an empty body is empty":
	var chunked: HttpExchange = scripted(
		["ab".to_bytes(), "cd".to_bytes(), "e".to_bytes()],
		200,
		"",
	)
	expect_equal(read_body(chunked)?.decode_utf8().get_or(""), "abcde")?

	var empty: HttpExchange = scripted([], 200, "")
	expect_equal(read_body(empty)?.length(), 0)?

fn bare(request: HttpRequest) HttpResponse:
	return HttpResponse(status: 200, body: "bare".to_bytes())

test "a response takes its defaults and reply sends it whole":
	var exchange: HttpExchange = scripted([], 200, "bare")
	reply(
		exchange,
		bare(
			HttpRequest(
				method: HttpMethod.Get,
				path: "/",
				query: "",
				headers: headers(),
				body: "".to_bytes(),
				protocol: "HTTP/1.1",
			)
		),
	)?
