// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A server on four threads with idle keep-alive connections does nothing while nobody sends
// a request: over a second it uses almost no CPU and its threads are woken a few times. The
// watcher looks every 2 ms only while a thread is busy and for 20 looks after the last
// one rests, and the sleep that ends the rest wakes it once, so the window holds one such run
// (about 20 wakes); a watcher that looked all the time would show 500 (the counters are the
// process's own, so any thread waking on a clock shows).
import (
	stdout from "@std/io/io.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	resource_usage from "@std/os/process.ms",
	seconds, sleep, nanoseconds from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn handle(request: HttpRequest) HttpResponse:
	return HttpResponse(200, f"ok {request.path} done\n".to_bytes())

fn warm(var conn: Connection) Bool!:
	send(var conn, "GET /warm HTTP/1.1\r\nHost: t\r\n\r\n")?
	var text = ""

	while not text.ends_with("done\n"):
		if chunk := recv(var conn, nanoseconds(10000000000)):
			if data := chunk:
				text = f"{text}{data.decode_utf8().get("?")}"
				continue

		return ok(false)

	return ok(text.starts_with("HTTP/1.1 200 OK"))

// Context switches are not counted on every platform (they read zero there), so the bound on
// them can only be met; the CPU bound is the same everywhere.
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
		warm(var a)?
		and warm(var b)?
		and warm(var c)?
		and warm(var d)?
		and warm(var e)?
		and warm(var f)?
	)
	// Let the threads come to rest after the last answer.
	sleep(seconds(1)).wait()?
	before := resource_usage()?
	sleep(seconds(1)).wait()?
	after := resource_usage()?
	cpu := (
		after.user_microseconds - before.user_microseconds
		+ after.system_microseconds - before.system_microseconds
	)
	switches := after.voluntary_switches - before.voluntary_switches
	a.close().get(none)
	b.close().get(none)
	c.close().get(none)
	d.close().get(none)
	e.close().get(none)
	f.close().get(none)
	server.close().get(none)
	return ok(warmed and cpu < 3000 and switches < 40)

export fn main() Int:
	asleep := run().get(false)
	_out := stdout().write(f"idle server stays asleep: {asleep}\n")
	if asleep: return 0

	return 1
