// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// While one handler computes without a wait, requests on the other connections of its
// thread are served by another thread. Each round holds a different thread; the client
// itself runs on one of them, so a round may freeze the client too, and one that does
// not must pass.
import (
	stdout from "@std/io/io.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	monotonic, nanoseconds from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn handle(request: HttpRequest) HttpResponse:
	if request.path == "/hold":
		started := monotonic()
		while monotonic().difference(started).to_milliseconds() < 400:
			continue

	return HttpResponse(200, headers(), f"ok {request.path} done\n".to_bytes())

fn ask(var conn: Connection, path: String) Void!:
	return send(var conn, f"GET {path} HTTP/1.1\r\nHost: t\r\n\r\n")

fn answer(var conn: Connection) Bool:
	var text = ""

	while not text.ends_with("done\n"):
		if chunk := recv(var conn, nanoseconds(10000000000)):
			if data := chunk:
				text = f"{text}{data.decode_utf8().get("?")}"
				continue

		return false

	return text.starts_with("HTTP/1.1 200 OK")

fn ask_two(var x: Connection, var y: Connection) Void!:
	ask(var x, "/fast")?
	return ask(var y, "/fast")

// Holds the thread of `held` and answers whether the others were served meanwhile.
// `pair` is the connection the server dealt to the same thread as `held`.
fn round(
	var held: Connection,
	var pair: Connection,
	var w: Connection,
	var x: Connection,
	var y: Connection,
	var z: Connection,
) Bool!:
	started := monotonic()
	ask(var held, "/hold")?
	ask(var pair, "/fast")?
	ask_two(var w, var x)?
	ask_two(var y, var z)?

	served := (
		answer(var pair)
		and answer(var w)
		and answer(var x)
		and answer(var y)
		and answer(var z)
	)
	others_ms := monotonic().difference(started).to_milliseconds()
	held_ok := answer(var held)
	held_ms := monotonic().difference(started).to_milliseconds()
	return ok(served and held_ok and others_ms * 2 < held_ms)

fn warm(var conn: Connection) Bool!:
	ask(var conn, "/warm")?
	return ok(answer(var conn))

// Three workers are dealt six connections in turn, so each thread has two: a and d, b
// and e, c and f.
fn run() Bool!:
	var server = serve(
		address: "127.0.0.1:0",
		handler: buffered(handle),
		options: HttpServerOptions(cores: 3),
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
	first := round(var a, var d, var b, var c, var e, var f)?
	second := round(var b, var e, var a, var c, var d, var f)?
	third := round(var c, var f, var a, var b, var d, var e)?
	a.close().get(none)
	b.close().get(none)
	c.close().get(none)
	d.close().get(none)
	e.close().get(none)
	f.close().get(none)
	server.close().get(none)
	return ok(warmed and (first or second or third))

export fn main() Int:
	served := run().get(false)
	_out := stdout().write(f"others served during a long handler: {served}\n")
	if served: return 0

	return 1
