// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
import (
	FetchOptions, fetch from "@std/net/fetch.ms",
	HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	milliseconds, sleep from "@std/time.ms",
)

fn route(request HttpRequest) HttpResponse {
	void sleep(milliseconds(2000)).wait()
	return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())
}

// The client gives up while the handler sleeps, and dropping the server cancels the
// accept loop, whose cleanup frees what it owns.
fn run() Bool {
	server := serve("127.0.0.1:0", buffered(route)).get()
	slow := fetch(
		f"http://{server.address()}/slow",
		FetchOptions(timeout: milliseconds(200)),
	).wait()
	return slow.is_error()
}

fn main() Void {
	print(if run() { "timed out" } else { "answered" })
	void sleep(milliseconds(500)).wait()
}
