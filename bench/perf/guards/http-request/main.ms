// Guard: a keep-alive HTTP request with the six headers a browser or curl sends costs a
// fixed number of instructions; with the argument `small` the request has only a Host
// header (`guard-http-request-small`). The shared body is in guard.ms.
import (
	arguments from "@std/os/env.ms",

	guard from "./guard.ms",
)

REQUEST := "GET /x?c=1 HTTP/1.1\r\nHost: b\r\nUser-Agent: curl/8.5.0\r\nAccept: */*\r\nAccept-Encoding: gzip, deflate\r\nAccept-Language: en-US,en;q=0.9\r\nConnection: keep-alive\r\n\r\n"
SMALL := "GET /x?c=1 HTTP/1.1\r\nHost: b\r\n\r\n"

// `main <own path> [small]`: the request with one header when `small` is given.
fn main() Int {
	return guard(if arguments().contains("small") { SMALL } else { REQUEST })
}
