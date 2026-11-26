// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A request that arrives on a connection while its handler is parked is served as soon
// as the handler's response is sent, not after a timeout.
import (
	Bytes from "@std/bytes.ms",
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	ReadStream, stdout from "@std/io/io.ms",
	HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	Duration, monotonic, nanoseconds, sleep from "@std/time.ms",
)

fn within(var input ReadStream[Bytes], timeout Duration) Bytes?! {
	return promise(() => input.next()).with(
		options: PromiseOptions(timeout: timeout.clone())
	).wait()
}

fn send(var conn Connection, text String) Void! {
	conn.output.write(text.to_bytes())?
	return conn.output.flush()
}

fn handle(request HttpRequest) HttpResponse {
	if request.path == "/slow" {
		void sleep(nanoseconds(200000000)).wait()
	}
	return HttpResponse(200, f"ok {request.path}\n".to_bytes())
}

fn exchange(address String) String {
	if var conn = connect(address).wait() {
		_first := send(conn, "GET /slow HTTP/1.1\r\nHost: t\r\n\r\n")

		// The slow handler is parked by now; the second request arrives while it waits.
		void sleep(nanoseconds(50000000)).wait()

		_second := send(
			conn,
			"GET /fast HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
		)
		var text = ""

		while true {
			if chunk := within(conn.input, nanoseconds(5000000000)) {
				data := chunk

				if data != null {
					text = f"{text}{(data.decode_utf8() or "?")}"
					continue
				}
			}

			break
		}

		void conn.close()
		return text
	}

	return "connect failed"
}

export fn main() Int {
	if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)) {
		var server = acquired
		start := monotonic()
		text := exchange(server.address())
		elapsed_ms := monotonic().difference(start).to_milliseconds()
		_count := stdout().write(
			f"responses: {text.split("HTTP/1.1 200 OK").length() - 1}\n"
		)
		_order := stdout().write(
			f"slow first: {(text.index_of("ok /slow") or (-1)) < (text.index_of("ok /fast") or (-1))}\n"
		)
		_prompt := stdout().write(f"prompt: {elapsed_ms < 2000}\n")
		void server.close()
		return 0
	}

	return 1
}
// expect-exit: 0
// expect-stdout: responses: 2
// expect-stdout: slow first: true
// expect-stdout: prompt: true
