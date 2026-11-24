// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A server on four threads with idle keep-alive connections does nothing while nobody
// sends a request: over a second it uses almost no CPU and its threads are woken a few
// times. The watcher looks every 2 ms only while a thread is busy and for 20 looks
// after the last one rests, and the sleep that ends the rest wakes it once, so the
// window holds one such run (about 20 wakes); a watcher that looked all the time would
// show 500 (the counters are the process's own, so any thread waking on a clock shows).
import (
	stdout from "@std/io/io.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	resource_usage from "@std/os/process.ms",
	nanoseconds, seconds, sleep from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn handle(request HttpRequest) HttpResponse:
	return HttpResponse(200, f"ok {request.path} done\n".to_bytes())

fn warm(var conn Connection) Bool!:
	send(conn, "GET /warm HTTP/1.1\r\nHost: t\r\n\r\n")?

	var text = ""

	while not text.ends_with("done\n"):
		if chunk := recv(conn, nanoseconds(10000000000)):
			data := chunk

			if data != null:
				text = f"{text}{(data.decode_utf8() or "?")}"
				continue

		return ok(false)

	return ok(text.starts_with("HTTP/1.1 200 OK"))

// Context switches are not counted on every platform (they read zero there), so the
// bound on them can only be met. CPU time is counted in clock ticks on Windows (15.6
// ms), so the bound allows several ticks (main measured 3 there); a thread that polled
// would use hundreds of ms in the window. The switch count is the sharp check
// elsewhere.
fn run() Bool!:
	var server = serve(
		address: "127.0.0.1:0",
		handler: buffered(handle),
		options: HttpServerOptions(cores: 4),
	)?
	var a = connect(server.address()).wait()?
	var b = connect(server.address()).wait()?
	var c = connect(server.address()).wait()?
	var d = connect(server.address()).wait()?
	var e = connect(server.address()).wait()?
	var f = connect(server.address()).wait()?
	warmed := (
		warm(a)?
		and warm(b)?
		and warm(c)?
		and warm(d)?
		and warm(e)?
		and warm(f)?
	)

	// Let the threads come to rest after the last answer.
	sleep(seconds(1)).wait()?

	before := resource_usage()?
	sleep(seconds(1)).wait()?

	after := resource_usage()?
	cpu := (
		after.user_microseconds
		- before.user_microseconds
		+ after.system_microseconds
		- before.system_microseconds
	)
	switches := after.voluntary_switches - before.voluntary_switches
	void a.close()
	void b.close()
	void c.close()
	void d.close()
	void e.close()
	void f.close()
	void server.close()

	asleep := warmed and cpu < 100000 and switches < 40
	if not asleep:
		_out := stdout().write(f"warmed {warmed}, cpu {cpu} us, switches {switches}\n")
	return ok(asleep)

export fn main() Int:
	asleep := run().get_or(false)
	_out := stdout().write(f"idle server stays asleep: {asleep}\n")
	if asleep: return 0

	return 1
