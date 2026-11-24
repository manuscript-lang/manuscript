// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	HttpResponse from "@std/net/http.ms",
	network from "@std/net/net.ms",
)

fn use() Void {
	shared := Map[Int, Int]()

	_server := network().serve(
		address: "127.0.0.1:0",
		handler: fn(request) HttpResponse {
			shared.add(key: 1, value: 2)
			return panic("unreached")
		}
	)
}
