// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// The same over HTTP/2: a connection with no open stream moves to another thread with its
// session. While one handler computes without a wait, requests on the other connections
// of its thread are served by another thread. Each round holds a different thread; the
// client itself may run on one of them, so a round may freeze the client too, and one that
// does not must pass.
import (
	Promise from "@std/concurrency/promise.ms",
	FetchOptions, FetchResponse, Fetcher, FetcherOptions, fetcher from "@std/net/fetch.ms",
	stdout from "@std/io/io.ms",
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	monotonic from "@std/time.ms",

	certificate, private_key from "./support/certificates.ms",
)

fn handle(request HttpRequest) HttpResponse:
	if request.path == "/hold":
		started := monotonic()
		while monotonic().difference(started).to_milliseconds() < 400:
			continue

	return HttpResponse(200, f"ok {request.path} done\n".to_bytes())

fn client_for() Fetcher!:
	return fetcher(
		FetcherOptions(
			tls: TlsOptions(roots_pem: certificate(), alpn: ["h2", "http/1.1"])
		)
	)

fn ask(c Fetcher, base String, path String) Promise[FetchResponse]:
	return c.fetch(f"{base}{path}", FetchOptions(timeout: 10.seconds()))

fn answered(promise Promise[FetchResponse]) Bool:
	match promise.wait():
		ok(response): return finished(response)
		error(_): return false

fn finished(response FetchResponse) Bool:
	text := response.text().get_or("")
	return response.head.protocol == "HTTP/2.0" and text.ends_with("done\n")

// Holds the thread of `held` and answers whether the others were served meanwhile. `pair`
// is the connection the server dealt to the same thread as `held`.
fn round(
	base String,
	held Fetcher,
	pair Fetcher,
	w Fetcher,
	x Fetcher,
	y Fetcher,
	z Fetcher,
) Bool:
	started := monotonic()
	slow := ask(held, base, "/hold")
	p1 := ask(pair, base, "/fast")
	p2 := ask(w, base, "/fast")
	p3 := ask(x, base, "/fast")
	p4 := ask(y, base, "/fast")
	p5 := ask(z, base, "/fast")
	served := answered(p1) and answered(p2) and answered(p3) and answered(p4) and answered(p5)
	others_ms := monotonic().difference(started).to_milliseconds()
	held_ok := answered(slow)
	held_ms := monotonic().difference(started).to_milliseconds()
	return served and held_ok and others_ms * 2 < held_ms

fn run() Bool!:
	var server = serve(
		address: "127.0.0.1:0",
		handler: buffered(handle),
		options: HttpServerOptions(
			cores: 3,
			tls: TlsOptions(
				certificate_pem: certificate(),
				private_key_pem: private_key(),
				alpn: ["h2", "http/1.1"],
			),
		),
	)?
	base := f"https://{server.address()}"
	a := client_for()?
	b := client_for()?
	c := client_for()?
	d := client_for()?
	e := client_for()?
	f := client_for()?
	// Three workers are dealt six connections in turn, so each thread has two: a and d, b
	// and e, c and f. The warm-up opens them in that order.
	warmed := (
		answered(ask(a, base, "/warm"))
		and answered(ask(b, base, "/warm"))
		and answered(ask(c, base, "/warm"))
		and answered(ask(d, base, "/warm"))
		and answered(ask(e, base, "/warm"))
		and answered(ask(f, base, "/warm"))
	)
	first := round(base, a, d, b, c, e, f)
	second := round(base, b, e, a, c, d, f)
	third := round(base, c, f, a, b, d, e)
	void server.close()
	return ok(warmed and (first or second or third))

export fn main() Int:
	served := run().get_or(false)
	_out := stdout().write(f"others served during a long handler: {served}\n")
	if served: return 0

	return 1
