// conform: tags=scope-cleanup,stdlib-net,tier-io
// conform: phase=run
// Starting a server parks while it binds. A cancel there unwinds out of the native that
// owns the handler, so the handler must be released on the way, or every cancelled
// `serve` leaks it (the leak check runs this fixture with the process-exit frees kept).
import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	microseconds, sleep from "@std/time.ms",
)

fn route(request HttpRequest) HttpResponse {
	return HttpResponse(status: 200, headers: headers(), body: request.path.to_bytes())
}

fn start() Void! {
	for i in 0..50 {
		server := serve("127.0.0.1:0", buffered(route))?
		server.close()?
	}
}

fn main() Void! {
	for round in 0..30 {
		stop := cancel_switch()
		starting := promise(
			() => start(),
			options: PromiseOptions(cancel: stop.signal()),
		)
		void sleep(microseconds(round * 150)).wait()?
		stop.cancel()
		void starting.wait()
	}

	print("done")
}
// expect-exit: 0
// expect-stdout: done
