// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A handler that returns an error is answered with a failure and its Error is released:
// the leak sweep (`make leak-check`) finds nothing left after many failing requests.
import (
	stdout from "@std/io/io.ms",
	HttpExchange from "@std/net/http.ms",
	connect, serve from "@std/net/net.ms",
)

fn failing(var exchange: HttpExchange) Void!:
	return error(
		Error(
			"the handler failed with a message that fills its own allocation",
			kind: "EIO",
		)
	)

fn fetch(address: String) Bool:
	if var conn = connect(address).wait():
		_sent := conn.output.write(
			"GET /x HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n".to_bytes()
		)
		_flushed := conn.output.flush()

		while true:
			read := conn.input.next()
			if read.is_error(): return false
			if _data := read.get(): continue

			return true

	return false

export fn main() Int:
	if acquired := serve(address: "127.0.0.1:0", handler: failing):
		var server = acquired
		var answered = 0
		for _at in 0..50:
			if fetch(server.address()): answered += 1
		void server.close()

		_line := stdout().write(f"answered {answered}\n")
		return 0

	return 1
