import (
	Bytes from "@std/bytes.ms",
	HttpExchange,
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers,
	reply,
	text from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_ok from "@std/test/test.ms",
	sleep from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn ok_route(request: HttpRequest) HttpResponse:
	return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

fn slow_route(request: HttpRequest) HttpResponse:
	_ := sleep(30.seconds()).wait()
	return HttpResponse(status: 200, headers: headers(), body: "late".to_bytes())

test "serve ends a connection that trickles its request head":
	server := serve(
		address: "127.0.0.1:0", handler: buffered(ok_route),
		options: HttpServerOptions(timeout: 400.milliseconds())
	) | try expect_ok
	var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	send(var client, "GET / HTTP/1.1\r\nHost: t\r\nX-Slow: ") | try expect_ok

	// One byte every 100 ms never completes the head; the budget still runs out.
	var sent = 0

	while sent < 30:
		_ := sleep(100.milliseconds()).wait()
		written := send(var client, "a")
		if written.is_error(): break

		sent += 1

	// The server closes the connection, so a write fails before the trickle ends. The
	// read may then see an error (a reset on macOS) instead of an end of stream.
	if sent == 30: return error(Error("trickled request head was never cut off"))

	if reply := recv(var client, 3.seconds()):
		text := reply.get(Bytes([])).decode_utf8().get("")
		if text.starts_with("HTTP/1.1 200"): return error(
			Error("incomplete request was served: {text}")
		)

test "close cancels a handler that outlives the grace period":
	var server = serve(
		address: "127.0.0.1:0", handler: buffered(slow_route),
		options: HttpServerOptions(grace: 200.milliseconds())
	) | try expect_ok
	var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	send(var client, "GET / HTTP/1.1\r\nHost: t\r\n\r\n") | try expect_ok

	_ := sleep(100.milliseconds()).wait()
	try server.close()

	// An error here is the connection ending (a reset on macOS); only a served reply fails.
	if reply := recv(var client, 5.seconds()):
		text := reply.get(Bytes([])).decode_utf8().get("")
		if text.starts_with("HTTP/1.1 200"): return error(
			Error("handler finished instead of being cancelled")
		)

test "close cancels a handler parked on a request body and releases its stream":
	var server = serve(
		address: "127.0.0.1:0", handler: buffered(ok_route),
		options: HttpServerOptions(grace: 0.seconds())
	) | try expect_ok
	var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok

	// The head promises a body that never comes, so the handler parks reading it. Cancelling it
	// must free the stream (`make leak-check` counts a leaked stream as a live block).
	send(var client, "POST / HTTP/1.1\r\nHost: t\r\nContent-Length: 100\r\n\r\nab") | try expect_ok

	_ := sleep(100.milliseconds()).wait()
	try server.close()

	if reply := recv(var client, 5.seconds()):
		text := reply.get(Bytes([])).decode_utf8().get("")
		if text.starts_with("HTTP/1.1 200"): return error(
			Error("handler finished instead of being cancelled")
		)

fn expect_file_reply(var conn: Connection) Unit!:
	reply := recv(var conn, 10.seconds()) | try expect_ok
	text := reply.get(Bytes([])).decode_utf8().get("")
	if not text.starts_with("HTTP/1.1 200"): return error(
		Error("file handler failed: {text}")
	)

test "serve answers requests while handlers read and write files":
	var dir = temporary("ms-http-io") | try expect_ok
	root := dir.path()
	payload := ("0123456789abcdef".repeat(262144) | try expect_ok).to_bytes()

	fn io_route(request: HttpRequest) HttpResponse:
		path := "{root}/slot{request.query}.bin"
		wrote := write_file(path, payload.clone(), replace: true).wait()
		if wrote.is_error(): return HttpResponse(500, headers(), "write".to_bytes())

		read := read_file(path).wait()
		if read.is_error(): return HttpResponse(500, headers(), "read".to_bytes())

		return HttpResponse(200, headers(), "{read.get().length()}".to_bytes())

	var server = serve(address: "127.0.0.1:0", handler: buffered(io_route)) | try expect_ok
	var a = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	var b = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	send(var a, "GET /io?1 HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n") | try expect_ok
	send(var b, "GET /io?2 HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n") | try expect_ok
	try expect_file_reply(var a)
	try expect_file_reply(var b)
	try server.close()
	try dir.close()

fn oversized(var exchange: HttpExchange) Unit!:
	return reply(var exchange, text(200, "z".repeat(5000).get("")))

test "serve answers 500 when a whole response exceeds max_response_bytes":
	server := serve(
		address: "127.0.0.1:0", handler: oversized,
		options: HttpServerOptions(max_response_bytes: 100)
	) | try expect_ok
	var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
	send(var client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n") | try expect_ok

	reply_bytes := recv(var client, 3.seconds()) | try expect_ok
	head := reply_bytes.get(Bytes([])).decode_utf8().get("")
	if not head.starts_with("HTTP/1.1 500"): return error(
		Error("expected a 500 reply, got: {head}")
	)

fn raw_status(address: String, request: String) String!:
	var client = connect(address, timeout: 2.seconds()).wait() | try expect_ok
	send(var client, request) | try expect_ok

	reply := recv(var client, 2.seconds()) | try expect_ok
	text := reply.get(Bytes([])).decode_utf8().get("")
	return ok(text.split("\r\n")[0].clone())

test "asterisk-form target is accepted only for OPTIONS":
	server := serve(address: "127.0.0.1:0", handler: buffered(ok_route)) | try expect_ok
	tail := "HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"
	get := raw_status(server.address(), "GET * {tail}") | try expect_ok
	options := raw_status(server.address(), "OPTIONS * {tail}") | try expect_ok
	if get != "HTTP/1.1 400 Bad Request": return error(Error("GET * answered: {get}"))
	if options != "HTTP/1.1 200 OK": return error(
		Error("OPTIONS * answered: {options}")
	)
