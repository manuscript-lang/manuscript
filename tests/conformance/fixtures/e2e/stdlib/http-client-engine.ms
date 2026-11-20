// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// The HTTP client against a hand-written server: a request, a redirect, a POST body,
// the size limit and an invalid URL.
import (
	Bytes, join from "@std/bytes.ms",
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	FetchBody, FetchOptions, fetch from "@std/net/fetch.ms",
	HttpMethod from "@std/net/http.ms",
	Connection, listen, request, restrict from "@std/net/net.ms",
	Duration, seconds from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

// Reads one request head; returns its text, or none at the end of the stream.
fn head_of(var conn: Connection) String?!:
	var text = ""

	while not text.contains("\r\n\r\n"):
		chunk := recv(conn, seconds(5))?

		if data := chunk:
			text += data.decode_utf8().get_or("")
		else:
			return ok(none)

	return ok(text)

fn reply(var conn: Connection, status: String, extra: String, body: String) Void!:
	return send(
		conn,
		f"HTTP/1.1 {status}\r\nContent-Length: {body.length()}\r\n{extra}\r\n{body}",
	)

fn if_typed(head: String) String:
	if head.lower().contains("content-type:"): return "typed"
	return "plain"

// Serves requests on one connection until the client leaves.
fn serve_one(var conn: Connection) Void!:
	while true:
		found := head_of(conn)?

		if text := found:
			if text.starts_with("GET /hello "):
				reply(conn, "200 OK", "X-Seen: yes\r\n", "hi")?
			else if text.starts_with("GET /old "):
				reply(conn, "302 Found", "Location: /hello\r\n", "")?
			else if text.starts_with("POST /moved "):
				reply(conn, "302 Found", "Location: /ct\r\n", "")?
			else if text.starts_with("GET /ct "):
				reply(conn, "200 OK", "", if_typed(text))?
			else if text.starts_with("POST /echo "):
				reply(conn, "200 OK", "", "posted")?
			else:
				reply(conn, "404 Not Found", "", "none")?
		else:
			return ok()

	return ok()

fn show(label: String, text: String) Void:
	_line := stdout().write(f"{label}: {text}\n")

fn kind_of[T](outcome: T!) String:
	match outcome:
		ok(_): return "ok"
		error(cause): return cause.kind.get_or("none")

fn run(base: String) Void!:
	first := fetch(f"{base}/hello").wait()?
	show("status", first.head.status.to_string())
	show("body", first.text().get_or("?"))
	show("header", first.head.headers.get("x-seen").get_or("-"))

	redirected := fetch(f"{base}/old").wait()?
	redirected_text := redirected.text().get_or("?")
	show("redirect", f"{redirected.head.status} {redirected_text}")

	posted := fetch(
		f"{base}/echo",
		FetchOptions(method: HttpMethod.Post, body: FetchBody.Text("data")),
	).wait()?
	show("post", posted.text().get_or("?"))

	moved := fetch(
		f"{base}/moved",
		FetchOptions(method: HttpMethod.Post, body: FetchBody.Text("data")),
	).wait()?
	show("moved", moved.text().get_or("?"))

	buffered := request(HttpMethod.Get, f"{base}/hello")?
	show("request", f"{buffered.head.status} {buffered.body.length()}")

	walled := restrict(["example.invalid"])?
	show("restricted", kind_of(walled.request(HttpMethod.Get, f"{base}/hello")))

	loopback := restrict([], ["127.0.0.0/8"])?
	inside := loopback.request(HttpMethod.Get, f"{base}/hello")?
	show("loopback", f"{inside.head.status}")

	scoped := restrict([], ["127.0.0.0/8"])?
	pooled := scoped.http_client()?
	scoped.close()
	show("closed", kind_of(pooled.request(HttpMethod.Get, f"{base}/hello")))
	show(
		"limit",
		kind_of(
			fetch(
				f"{base}/hello",
				FetchOptions(max_response_bytes: 1),
			).wait()
		),
	)
	show("scheme", kind_of(fetch("ftp://example.com/").wait()))
	return ok()

export fn main() Int:
	if listener := listen("127.0.0.1:0"):
		base := f"http://{listener.address()}"
		client := promise(
			fn: run(base),
			options: PromiseOptions(placement: Placement.Here)
		)

		// One connection for each request that reaches the server.
		for turn in 0..7:
			if var conn = listener.accept().wait():
				_served := serve_one(conn)
				void conn.close()

		finished := client.wait()
		show("result", kind_of(finished))
		void listener.close()
		return 0

	return 1
