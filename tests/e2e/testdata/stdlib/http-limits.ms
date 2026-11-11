import (
	Bytes from "@std/bytes.ms",
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
	server := serve(address: "127.0.0.1:0", handler: buffered(ok_route)) | try expect_ok
	var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	filler := "a".repeat(2000000) | try expect_ok
	head := "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\nX: {filler}\r\n\r\n"

	// The server may answer and close before the whole head is written.
	_written := send(var client, head)
	reply := recv(var client, 5.seconds()) | try expect_ok
	text := reply.get().decode_utf8().get("")
	if not text.starts_with("HTTP/1.1 431"): return error(
		Error("oversized header block was not rejected: {text}")
	)

test "serve timeout closes idle connections":
	handler := ok_route
	server := serve(
		address: "127.0.0.1:0", handler: buffered(handler),
		options: HttpServerOptions(timeout: 300.milliseconds())
	) | try expect_ok
	var silent = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	closed := recv(var silent, 3.seconds()) | try expect_ok
	if _data := closed: return error(Error("silent connection was answered"))

	try silent.close()

	var reused = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	send(var reused, "GET / HTTP/1.1\r\nHost: t\r\n\r\n") | try expect_ok

	first := recv(var reused, 2.seconds()) | try expect_ok
	answered := first.get(Bytes([]))
	if answered.is_empty(): return error(Error("no response"))

	after := recv(var reused, 3.seconds()) | try expect_ok
	if _data := after: return error(Error("idle keep-alive connection stayed open"))

test "serve rejects a zero request timeout":
	failure := try expect_error(
		serve(
			address: "127.0.0.1:0", handler: buffered(ok_route),
			options: HttpServerOptions(timeout: 0.seconds())
		)
	)
	try expect_equal(failure, Error("HTTP: invalid input", kind: "EINVAL"))
