// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// The same over TLS: a session moves to another thread with its connection. While one
// handler computes without a wait, requests on the other connections of its thread are
// served by another thread. Each round holds a different thread; the client itself runs
// on one of them, so a round may freeze the client too, and one that does not must
// pass.
import (
	stdout from "@std/io/io.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	monotonic, nanoseconds from "@std/time.ms",

	certificate, private_key from "./support/certificates.ms",
	recv, send from "./support/conn.ms",
)

fn client_tls() TlsOptions {
	return TlsOptions(
		server_name: "stdlib.test",
		roots_pem: certificate(),
		certificate_pem: "",
		private_key_pem: "",
		alpn: ["http/1.1"],
		require_client_certificate: false,
	)
}

fn server_tls() TlsOptions {
	return TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: certificate(),
		private_key_pem: private_key(),
		alpn: ["http/1.1"],
		require_client_certificate: false,
	)
}

fn handle(request HttpRequest) HttpResponse {
	if request.path == "/hold" {
		started := monotonic()
		while monotonic().difference(started).to_milliseconds() < 400 {
			continue
		}
	}

	return HttpResponse(200, f"ok {request.path} done\n".to_bytes())
}

fn ask(var conn Connection, path String) Void! {
	return send(conn, f"GET {path} HTTP/1.1\r\nHost: t\r\n\r\n")
}

fn answer(var conn Connection) Bool {
	var text = ""

	while not text.ends_with("done\n") {
		if chunk := recv(conn, nanoseconds(10000000000)) {
			data := chunk

			if data != null {
				text = f"{text}{(data.decode_utf8() or "?")}"
				continue
			}
		}

		return false
	}

	return text.starts_with("HTTP/1.1 200 OK")
}

fn ask_two(var x Connection, var y Connection) Void! {
	ask(x, "/fast")?
	return ask(y, "/fast")
}

// Holds the thread of `held` and answers whether the others were served meanwhile.
// `pair` is the connection the server dealt to the same thread as `held`.
fn round(
	var held Connection,
	var pair Connection,
	var w Connection,
	var x Connection,
	var y Connection,
	var z Connection,
) Bool! {
	started := monotonic()
	ask(held, "/hold")?
	ask(pair, "/fast")?
	ask_two(w, x)?
	ask_two(y, z)?

	served := (answer(pair) and answer(w) and answer(x) and answer(y) and answer(z))
	others_ms := monotonic().difference(started).to_milliseconds()
	held_ok := answer(held)
	held_ms := monotonic().difference(started).to_milliseconds()
	return ok(served and held_ok and others_ms * 2 < held_ms)
}

fn warm(var conn Connection) Bool! {
	ask(conn, "/warm")?
	return ok(answer(conn))
}

// Three workers are dealt six connections in turn, so each thread has two: a and d, b
// and e, c and f.
fn run() Bool! {
	var server = serve(
		address: "127.0.0.1:0",
		handler: buffered(handle),
		options: HttpServerOptions(cores: 3, tls: server_tls()),
	)?
	var a = connect(server.address(), tls: client_tls(), timeout: 5.seconds()).wait()?
	var b = connect(server.address(), tls: client_tls(), timeout: 5.seconds()).wait()?
	var c = connect(server.address(), tls: client_tls(), timeout: 5.seconds()).wait()?
	var d = connect(server.address(), tls: client_tls(), timeout: 5.seconds()).wait()?
	var e = connect(server.address(), tls: client_tls(), timeout: 5.seconds()).wait()?
	var f = connect(server.address(), tls: client_tls(), timeout: 5.seconds()).wait()?
	warmed := (
		warm(a)?
		and warm(b)?
		and warm(c)?
		and warm(d)?
		and warm(e)?
		and warm(f)?
	)
	first := round(a, d, b, c, e, f)?
	second := round(b, e, a, c, d, f)?
	third := round(c, f, a, b, d, e)?
	void a.close()
	void b.close()
	void c.close()
	void d.close()
	void e.close()
	void f.close()
	void server.close()
	return ok(warmed and (first or second or third))
}

export fn main() Int {
	served := run().get_or(false)
	_out := stdout().write(f"others served during a long handler: {served}\n")
	if served { return 0 }

	return 1
}
// expect-exit: 0
// expect-stdout: others served during a long handler: true
