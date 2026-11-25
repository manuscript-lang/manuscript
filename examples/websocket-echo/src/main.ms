import (
	HttpExchange from "@std/net/http.ms",
	serve from "@std/net/net.ms",
)

// Echoes every message back until the peer closes the connection.
fn echo(var exchange HttpExchange) Void! {
	var socket = exchange.upgrade(
		allowed_origins: [],
		subprotocols: [],
		max_message_bytes: 65536,
	)?

	while true {
		message := socket.input.next()?
		m := message

		if m != null {
			socket.output.write(m)?
		} else {
			break
		}
	}

	socket.close()?
	return ok()
}

fn main() Void! {
	server := serve(address: "127.0.0.1:8080", handler: echo)?
	print(f"websocket echo on ws://{server.address()}/")
	server.wait()?
}
