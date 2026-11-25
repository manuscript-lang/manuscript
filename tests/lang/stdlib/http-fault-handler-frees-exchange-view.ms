// conform: tags=stdlib-http,stdlib-net,tier-io
// conform: phase=run
import (
	FetchOptions, fetch from "@std/net/fetch.ms",
	HttpExchange from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	milliseconds, sleep from "@std/time.ms",
)

fn faulting(var exchange HttpExchange) Void! {
	xs List[Int] := []
	n := xs[5]
	if n > 5 { return ok() }
}

// The thunk that calls the handler keeps the exchange in a stack slot; a fault in the
// handler still releases it.
fn status() Int {
	server := serve("127.0.0.1:0", faulting).get()
	reply := fetch(
		f"http://{server.address()}/",
		FetchOptions(timeout: milliseconds(2000)),
	).wait()
	return reply.get().head.status
}

fn main() Void {
	print(status())
	void sleep(milliseconds(300)).wait()
}
