// conform: tags=stdlib-net,tier-io
// conform: phase=run
// conform: timeout=30
// A connection to a host name resolves it through the event loop (libuv's getaddrinfo
// on every platform) and then connects; the server sees the client and bytes cross.
import (
	stdout from "@std/io/io.ms",
	connect, listen from "@std/net/net.ms",
	seconds from "@std/time.ms",

	recv, send from "./support/conn.ms",
)

fn run() Bool!:
	listener := listen(":0")?
	port := listener.address().rsplit_once(":").get().after
	var client = connect(f"localhost:{port}", timeout: 5.seconds()).wait()?
	var server = listener.accept(5.seconds()).wait()?
	send(client, "ping")?

	got := recv(server, 5.seconds())?
	return ok(got.get().decode_utf8().get_or("") == "ping")

export fn main() Int:
	reached := run().get_or(false)
	_out := stdout().write(f"connected by host name: {reached}\n")
	if reached: return 0

	return 1
