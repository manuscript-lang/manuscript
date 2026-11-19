// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A handler that is still waiting when the server's request timeout passes is cancelled
// and the request is answered 504, with or without a grace period; the server keeps
// serving afterwards.
import (
	Bytes from "@std/bytes.ms",
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	ReadStream, stderr, stdout from "@std/io/io.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	Duration, monotonic, nanoseconds, sleep from "@std/time.ms",
)

fn within(var input: ReadStream[Bytes], timeout: Duration) Bytes?!:
	return promise(fn: input.next()).with(
		options: PromiseOptions(timeout: timeout)
	).wait()

fn send(var conn: Connection, text: String) Void!:
	conn.output.write(text.to_bytes())?
	return conn.output.flush()

fn handle(request: HttpRequest) HttpResponse:
	if request.path == "/slow":
		void sleep(nanoseconds(3000000000)).wait()
	return HttpResponse(200, f"ok {request.path}\n".to_bytes())

fn fetch(address: String, path: String) String:
	if var conn = connect(address).wait():
		_sent := send(
			var conn,
			f"GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
		)
		var text = ""

		while true:
			read := within(var conn.input, nanoseconds(5000000000))

			if read.is_error():
				// A flake on a slow runner must say why the reply never arrived.
				text = f"{text}[read failed: {read.err().kind} {read.err().message}]"
				break

			if data := read.get():
				text = f"{text}{data.decode_utf8().get_or("?")}"
				continue

			break

		void conn.close()
		return text

	return "connect failed"

fn run(label: String, grace_ms: Int) Bool:
	options := HttpServerOptions(
		timeout: nanoseconds(200000000),
		grace: nanoseconds(grace_ms * 1000000),
	)

	if acquired := serve(
		address: "127.0.0.1:0",
		handler: buffered(handle),
		options: options,
	):
		var server = acquired
		start := monotonic()
		slow := fetch(server.address(), "/slow")
		elapsed_ms := monotonic().difference(start).to_milliseconds()
		fast := fetch(server.address(), "/fast")
		_slow := stdout().write(
			f"{label} slow: {slow.starts_with("HTTP/1.1 504")} prompt: {elapsed_ms < 2000}\n"
		)
		if not slow.starts_with("HTTP/1.1 504"):
			_seen := stderr().write(f"{label} slow answer: {slow}\n")

		_fast := stdout().write(
			f"{label} fast: {fast.starts_with("HTTP/1.1 200 OK")}\n"
		)
		void server.close()
		return true

	return false

// The first connection of a process pays for lazy start-up (sockets, scheduler threads,
// first page faults), which on a loaded Windows runner exceeded the 200 ms request
// budget under test and closed the idle connection before its request arrived. Pay it
// here, outside any timeout.
fn warm() Bool:
	if acquired := serve(address: "127.0.0.1:0", handler: buffered(handle)):
		var server = acquired
		answer := fetch(server.address(), "/fast")
		void server.close()
		return answer.starts_with("HTTP/1.1 200 OK")

	return false

export fn main() Int:
	if not warm(): return 1

	if run("no grace", 0):
		if run("grace", 500): return 0
	return 1
