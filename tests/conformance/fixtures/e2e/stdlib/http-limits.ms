// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	panic from "@std/core.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	connect, serve from "@std/net/net.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	recv, send from "./support/conn.ms",
)

fn ok_route(request: HttpRequest) HttpResponse:
	return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

test "serve caps the request header block":
	server := serve(address: "127.0.0.1:0", handler: buffered(ok_route)) | expect_ok?
	var client = connect(server.address(), timeout: 2.seconds()).wait() | expect_ok?
	filler := "a".repeat(2000000)
	head := f"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\nX: {filler}\r\n\r\n"

	// The server may answer and close before the whole head is written.
	_written := send(client, head)
	reply := recv(client, 5.seconds()) | expect_ok?
	text := (reply or panic("called Optional.get() on null")).decode_utf8() or ""
	if not text.starts_with("HTTP/1.1 431"): return error(
		Error(f"oversized header block was not rejected: {text}")
	)

test "serve timeout closes idle connections":
	handler := ok_route
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: buffered(handler),
			options: HttpServerOptions(timeout: 300.milliseconds()),
		) | expect_ok?
	)
	var silent = connect(server.address(), timeout: 2.seconds()).wait() | expect_ok?
	closed := recv(silent, 3.seconds()) | expect_ok?
	_data := closed
	if _data != null: return error(Error("silent connection was answered"))

	silent.close()?

	var reused = connect(server.address(), timeout: 2.seconds()).wait() | expect_ok?
	send(reused, "GET / HTTP/1.1\r\nHost: t\r\n\r\n") | expect_ok?

	first := recv(reused, 2.seconds()) | expect_ok?
	answered := first or Bytes([])
	if answered.is_empty(): return error(Error("no response"))

	after := recv(reused, 3.seconds()) | expect_ok?
	_data := after
	if _data != null: return error(Error("idle keep-alive connection stayed open"))

test "serve rejects a zero request timeout":
	failure := expect_error(
		serve(
			address: "127.0.0.1:0",
			handler: buffered(ok_route),
			options: HttpServerOptions(timeout: 0.seconds()),
		)
	)?
	expect_equal(failure, Error("HTTP: invalid input", kind: "EINVAL"))?
