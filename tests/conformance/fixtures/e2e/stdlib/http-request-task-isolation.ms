// conform: tags=testing,stdlib-http,stdlib-net,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	HttpExchange,
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	connect, serve from "@std/net/net.ms",
	expect_ok from "@std/test/test.ms",
	sleep from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn route(request HttpRequest) HttpResponse {
	if request.path == "/big" {
		return HttpResponse(
			status: 200,
			headers: headers(),
			body: "x".repeat(1000).to_bytes(),
		)
	}
	return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())
}

fn get(address String, path String) String! {
	var client = connect(address, timeout: 2.seconds()).wait()?
	send(client, f"GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")?

	reply := recv(client, 3.seconds())?
	return ok((reply or Bytes([])).decode_utf8() or "")
}

test "a response over the limit fails its request and the server answers the next" {
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: buffered(route),
			options: HttpServerOptions(max_response_bytes: 100),
		) | expect_ok?
	)

	for i in 0..5 {
		big := get(server.address(), "/big")?
		if not big.starts_with(
			"HTTP/1.1 500"
		) { return error(Error(f"over the limit: {big}")) }

		small := get(server.address(), "/small")?
		if not small.starts_with(
			"HTTP/1.1 200"
		) { return error(Error(f"after: {small}")) }
	}
}

fn hanging(var exchange HttpExchange) Void! {
	sleep(30.seconds()).wait()?
}

test "closing in the turn a request task was started ends it and returns" {
	for i in 0..20 {
		var server = (
			serve(
				address: "127.0.0.1:0",
				handler: hanging,
				options: HttpServerOptions(grace: 0.seconds()),
			) | expect_ok?
		)
		var client = connect(server.address(), timeout: 2.seconds()).wait() | expect_ok?
		send(client, "GET / HTTP/1.1\r\nHost: t\r\n\r\n")?

		// The request may or may not have reached a handler yet; close must not wait
		// for it.
		server.close() | expect_ok?
	}
}
