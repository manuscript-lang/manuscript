// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=test
// conform: timeout=30
// A client that sends part of a request and closes its sending side at once must see
// the connection end promptly. The server has no request timeout here, so a missed end
// of stream would leave the connection open forever.
import (
	HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	expect_ok, expect_true from "@std/test/test.ms",
	milliseconds from "@std/time.ms",
)

fn handle(request: HttpRequest) HttpResponse:
	return HttpResponse(200, "ok\n".to_bytes())

// True when the server closed the connection within two seconds of the half-close.
fn ends_promptly(address: String, partial: String) Bool!:
	var conn = connect(address).wait()?
	conn.output.write(partial.to_bytes())?
	conn.output.flush()?
	conn.output.end()?

	next := conn.input.next(timeout: milliseconds(2000))
	if closed := next: return ok(closed == null)

	return ok(false)

test "a half-closed partial request ends the connection":
	server := serve(address: "127.0.0.1:0", handler: buffered(handle)) | expect_ok?
	var round = 0

	while round < 40:
		ended := (
			ends_promptly(
				server.address(),
				"GET /x HTTP/1.1\r\nHost: t\r\n",
			) | expect_ok?
		)
		void expect_true(ended)?
		round += 1

	return ok()
