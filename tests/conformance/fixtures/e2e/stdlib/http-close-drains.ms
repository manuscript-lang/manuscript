// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// Closing a server lets a response in progress finish; `wait` returns as soon as it
// has.
import (
	Bytes from "@std/bytes.ms",
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	ReadStream, stdout from "@std/io/io.ms",
	HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	remove, stat, temporary_directory, write_file from "@std/os/fs.ms",
	Duration, monotonic, nanoseconds, sleep from "@std/time.ms",
)

fn within(var input: ReadStream[Bytes], timeout: Duration) Bytes?!:
	return promise(fn: input.next()).with(
		options: PromiseOptions(timeout: timeout)
	).wait()

fn send(var conn: Connection, text: String) Void!:
	conn.output.write(text.to_bytes())?
	return conn.output.flush()

// The handler announces itself in the directory the request names, so the test closes
// the server only once a response is truly in progress, however slowly a loaded machine
// reads the request, and concurrent runs never see each other's marker.
fn handle(request: HttpRequest) HttpResponse:
	for dir in request.headers.get_all("x-marker-dir"):
		_announced := write_file(f"{dir}/started", "started".to_bytes()).wait()
	void sleep(nanoseconds(300000000)).wait()
	return HttpResponse(200, "done\n".to_bytes())

export fn main() Int:
	if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
		var server = acquired
		dir := temporary_directory("ms-http-close-drains-*").get_or("")

		if var conn = connect(server.address()).wait():
			_sent := send(
				conn,
				f"GET /slow HTTP/1.1\r\nHost: t\r\nX-Marker-Dir: {dir}\r\n\r\n",
			)

			// Wait until the handler has started.
			var tries = 0

			while tries < 1000 and stat(f"{dir}/started").is_error():
				void sleep(nanoseconds(10000000)).wait()
				tries += 1

			start := monotonic()
			void server.close()

			close_ms := monotonic().difference(start).to_milliseconds()
			var text = ""

			while true:
				if chunk := within(conn.input, nanoseconds(5000000000)):
					data := chunk

					if data != null:
						text = f"{text}{(data.decode_utf8() or "?")}"
						continue

				break

			void conn.close()

			_removed := remove(dir, recursive: true)
			_status := stdout().write(
				f"answered: {text.starts_with("HTTP/1.1 200 OK")}\n"
			)
			_waited := stdout().write(
				f"close waited for the handler: {close_ms >= 200}\n"
			)
			_prompt := stdout().write(f"close returned promptly: {close_ms < 2000}\n")
			return 0

	return 1
