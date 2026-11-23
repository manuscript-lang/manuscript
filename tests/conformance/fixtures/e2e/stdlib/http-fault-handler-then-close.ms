// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	HttpExchange from "@std/net/http.ms",
	connect, serve from "@std/net/net.ms",
	expect_ok, expect_true from "@std/test/test.ms",

	recv, send from "./support/conn.ms",
)

fn faulting(var exchange: HttpExchange) Void!:
	xs: List[Int] := []
	n := xs[1000000]
	if n > 5: return ok()

test "closing a server whose handler faulted frees the worker once":
	server := serve(address: "127.0.0.1:0", handler: faulting) | expect_ok?

	for i in 0..3:
		var client = connect(server.address(), timeout: 2.seconds()).wait() | expect_ok?
		send(client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")?

		reply_bytes := recv(client, 3.seconds())?
		head := reply_bytes.get_or(Bytes([])).decode_utf8().get_or("")
		expect_true(head.starts_with("HTTP/1.1 500"))?

	server.close() | expect_ok?
