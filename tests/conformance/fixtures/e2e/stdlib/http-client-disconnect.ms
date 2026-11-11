// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A handler whose client went away is cancelled: its wait ends and its cleanup runs.
import (
	Closeable from "@std/core.ms",
	stdout from "@std/io/io.ms",
	HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	nanoseconds, sleep from "@std/time.ms",
)

fn send(var conn: Connection, text: String) Unit!:
	conn.output.write(text.to_bytes())?
	return conn.output.flush()

type Reporter:
	name: String

impl Closeable for Reporter:
	var fn close() Unit!:
		_line := stdout().write("{self.name} cleanup ran\n")

fn handle(request: HttpRequest) HttpResponse:
	var _reporter = Reporter("handler")
	_ := sleep(nanoseconds(30000000000)).wait()
	_reporter.close().get(none)
	return HttpResponse(200, headers(), "late\n".to_bytes())

export fn main() Int:
	if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
		var server = acquired

		if var conn = connect(server.address()).wait():
			_sent := send(var conn, "GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

			// Let the handler start, then leave without waiting for the response.
			_ := sleep(nanoseconds(100000000)).wait()
			conn.close().get(none)

			_ := sleep(nanoseconds(500000000)).wait()
			_done := stdout().write("done\n")
			server.close().get(none)
			return 0

	return 1
