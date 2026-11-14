// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	PromiseOptions from "@std/concurrency/promise.ms",
	fetch from "@std/net/fetch.ms",
	HttpExchange, HttpServer, HttpServerOptions from "@std/net/http.ms",
	connect, serve from "@std/net/net.ms",
	memory_usage from "@std/os/system.ms",
	expect_ok from "@std/test/test.ms",
	sleep from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn faulting(var exchange: HttpExchange) Unit!:
	big := "x".repeat(1000000).get("")
	xs: List[Int] := []
	n := xs[big.length()]
	if big.length() + n > 5: return ok(unit)

test "a faulting handler releases the values its frames own":
	server := serve(address: "127.0.0.1:0", handler: faulting) | expect_ok?
	before := (memory_usage() | expect_ok?).resident

	for i in 0..60:
		var client = connect(server.address(), timeout: 2.seconds()).wait() | expect_ok?
		send(var client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")?

		reply_bytes := recv(var client, 3.seconds())?
		head := reply_bytes.get(Bytes([])).decode_utf8().get("")
		if not head.starts_with("HTTP/1.1 500"): return error(Error(head))

	// Each leaked fault kept 1 MB, so 60 faults would grow the process by 60 MB.
	grown := (memory_usage() | expect_ok?).resident - before
	if grown > 20000000: return error(Error("resident memory grew {grown} bytes"))

fn hanging(var exchange: HttpExchange) Unit!:
	sleep(30.seconds()).wait()?

// Closing cancels the hanging handlers at once rather than waiting out their sleep.
fn hanging_server() HttpServer!:
	return serve(
		address: "127.0.0.1:0",
		handler: hanging,
		options: HttpServerOptions(grace: 0.seconds()),
	)

test "a fetch cancelled by its timeout releases its read buffer":
	server := hanging_server()?
	url := "http://{server.address()}/"

	// Warm up the thread's buffers and the connection pool before measuring.
	for i in 0..20:
		_ := fetch(url).with(options: PromiseOptions(timeout: 1.milliseconds())).wait()

	before := (memory_usage() | expect_ok?).resident

	for i in 0..300:
		timed_out := fetch(url).with(
			options: PromiseOptions(timeout: 1.milliseconds())
		).wait()
		if timed_out.is_ok(): return error(Error("a hanging handler answered"))

	// Each cancelled read leaked a 64 KiB buffer, so 300 fetches grew the process by
	// about 19 MB.
	grown := (memory_usage() | expect_ok?).resident - before
	if grown > 8000000: return error(Error("resident memory grew {grown} bytes"))

test "a fetch cancelled by its timeout frees the request state its frames own":
	server := hanging_server()?
	url := "http://{server.address()}/"

	// One fetch waits long enough for its request to be sent; the rest cancel at once.
	_ := fetch(url).with(options: PromiseOptions(timeout: 5.milliseconds())).wait()
	for i in 0..200:
		_ := fetch(url).with(options: PromiseOptions(timeout: 0.milliseconds())).wait()

	before := (memory_usage() | expect_ok?).heap_used

	for i in 0..2000:
		timed_out := fetch(url).with(
			options: PromiseOptions(timeout: 0.milliseconds())
		).wait()
		if timed_out.is_ok(): return error(Error("a hanging handler answered"))

	// The method, URLs, header vectors and pool key leaked about 340 bytes per
	// cancelled fetch.
	grown := (memory_usage() | expect_ok?).heap_used - before
	if grown > 2000 * 64: return error(
		Error("heap grew {grown} bytes over 2000 cancelled fetches")
	)

test "a fetch cancelled while it waits for the response frees the cancellation error":
	server := hanging_server()?
	url := "http://{server.address()}/"

	// The first fetches warm the connection pool and the thread's buffers.
	for i in 0..20:
		_ := fetch(url).with(options: PromiseOptions(timeout: 5.milliseconds())).wait()

	before := (memory_usage() | expect_ok?).heap_used

	for i in 0..400:
		timed_out := fetch(url).with(
			options: PromiseOptions(timeout: 3.milliseconds())
		).wait()
		if timed_out.is_ok(): return error(Error("a hanging handler answered"))

	// The error a cancelled read returns is dropped before the boundary jumps into the
	// runtime's cancellation; keeping it leaked its text on every cancelled call.
	grown := (memory_usage() | expect_ok?).heap_used - before
	if grown > 512: return error(
		Error("heap grew {grown} bytes over 400 fetches cancelled while reading")
	)
