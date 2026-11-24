// conform: tags=stdlib-http,stdlib-net,scope-cleanup,tier-io
// conform: phase=run
// conform: timeout=30
// Closing a server with no grace while a handler waits cancels the handler and frees
// the request: the exchange, its headers and the response being written (the leak check
// counts live blocks at exit).
import (
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	Connection, connect, serve from "@std/net/net.ms",
	milliseconds, seconds, sleep from "@std/time.ms",
)

fn route(request HttpRequest) HttpResponse:
	void sleep(seconds(30)).wait()
	return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

fn once(requests Int) Void!:
	var server = serve(
		"127.0.0.1:0",
		buffered(route),
		HttpServerOptions(grace: milliseconds(0)),
	)?

	if requests == 0:
		void server.close()
		return ok()

	var conn = connect(server.address()).wait()?
	conn.output.write("GET /slow HTTP/1.1\r\nHost: t\r\n\r\n".to_bytes())?
	conn.output.flush()?
	void sleep(milliseconds(50)).wait()
	void server.close()
	void conn.close()
	return ok()

fn main() Void:
	for i in 0..3:
		void once(1)
	void sleep(milliseconds(100)).wait()
	print("done")
