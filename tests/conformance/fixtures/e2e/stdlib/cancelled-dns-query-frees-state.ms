// conform: tags=scope-cleanup,stdlib-net,tier-io
// conform: phase=run
// A DNS lookup cancelled while it waits for the server unwinds out of the datagram or connection native it
// was in: the query's socket, buffers and name list must be freed on the way, or every cancelled lookup
// leaks them (the leak check runs this fixture with the process-exit frees kept).
import (
	PromiseOptions, cancel_switch, promise from "@std/concurrency/promise.ms",
	DnsKind from "@std/net/ip.ms",
	DnsOptions, bind_datagram, with_resolver from "@std/net/net.ms",
	milliseconds, seconds, sleep from "@std/time.ms",
)

fn main() Void!:
	// The server is bound but never answers, so each lookup waits until it is cancelled.
	silent := bind_datagram("127.0.0.1:0")?
	network := with_resolver(silent.address.clone())?

	for round in 0..8:
		stop := cancel_switch()
		asking := promise(
			() => network.resolve_dns(
				"example.test",
				DnsKind.A,
				DnsOptions(timeout: seconds(30)),
			),
			options: PromiseOptions(cancel: stop.signal()),
		)
		void sleep(milliseconds(5 + round * 3)).wait()?
		stop.cancel()
		void asking.wait()

	print("done")
