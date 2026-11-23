// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	forward from "@std/io/forward.ms",
	ReadStream, WriteStream, pipe from "@std/io/io.ms",
	HttpExchange, HttpServerOptions from "@std/net/http.ms",
	serve, web_socket from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	WebSocket,
	WebSocketKind,
	WebSocketMessage,
	WebSocketOptions from "@std/net/websocket.ms",
	expect_equal from "@std/test/test.ms",

	within from "./support/conn.ms",
	text_headers from "./support/http.ms",
)

// What a handler tells the room. A join carries the write end of the member's own
// websocket output (shared with `forward`), moved through the room's pipe, so the owner
// can push to it later.
enum Command:
	Join(out: WriteStream[WebSocketMessage])
	Say(text: String)

fn room_owner(var inbox: ReadStream[Command]) Void!:
	var members: List[WriteStream[WebSocketMessage]] = []

	for command in inbox:
		match command:
			Command.Join(out):
				members.append(out)
			Command.Say(text):
				var i = 0

				while i < members.length():
					if members[i].write(
						WebSocketMessage(
							text.to_bytes(),
							WebSocketKind.Text,
						)
					).is_error():
						members.remove(i)
					else:
						i += 1

fn tls_options() TlsOptions:
	return TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: "",
		private_key_pem: "",
		alpn: [],
		require_client_certificate: false,
	)

test "a room owner pushes each line to every connected websocket":
	var room = pipe[Command](capacity: 16)
	var inbox = room.reader()
	var gate = room.writer()
	owner := promise(fn: room_owner(inbox))

	handler := fn(var exchange: HttpExchange) Void!:
		socket := exchange.upgrade(
			allowed_origins: [],
			subprotocols: [],
			max_message_bytes: 1024,
		)?
		var {input, output} = socket
		var cmds = room.writer()
		cmds.write(Command.Join(forward(output)))?

		while true:
			message := input.next()?
			m := message

			if m != null:
				text := m.data.decode_utf8()
				if text != null:
					cmds.write(Command.Say(text))?
			else:
				break

		return ok()

	server := serve(
		address: "127.0.0.1:0",
		handler: handler,
		options: HttpServerOptions(
			timeout: 5.seconds(),
			grace: 0.seconds(),
			tls: null,
		),
	)?
	client_options := WebSocketOptions(
		headers: (text_headers(Map[String, String]())?),
		subprotocols: [],
		max_message_bytes: 1024,
		timeout: 2.seconds(),
		tls: tls_options(),
		compression: false,
	)
	var alice = web_socket(
		url: f"ws://{server.address()}/",
		options: client_options.clone(),
	)?

	// Each client waits to hear its own line, which proves the room holds its output,
	// before the next one speaks.
	alice.output.write(WebSocketMessage("a".to_bytes(), WebSocketKind.Text))?
	expect_equal(heard(alice)?, "a")?

	var bob = web_socket(url: f"ws://{server.address()}/", options: client_options)?
	bob.output.write(WebSocketMessage("b".to_bytes(), WebSocketKind.Text))?
	expect_equal(heard(bob)?, "b")?
	expect_equal(heard(alice)?, "b")?
	alice.output.write(WebSocketMessage("hi".to_bytes(), WebSocketKind.Text))?
	expect_equal(heard(bob)?, "hi")?
	expect_equal(heard(alice)?, "hi")?

	// A client that leaves is dropped on the next line; the room keeps serving the
	// rest.
	bob.close()?
	alice.output.write(WebSocketMessage("one".to_bytes(), WebSocketKind.Text))?
	expect_equal(heard(alice)?, "one")?
	alice.output.write(WebSocketMessage("two".to_bytes(), WebSocketKind.Text))?
	expect_equal(heard(alice)?, "two")?

	// Once every client and the gate are closed, the owner ends and closes what it
	// held.
	alice.close()?
	gate.close()?
	server.close()?
	owner.wait()?

fn heard(var socket: WebSocket) String!:
	message := (within(socket.input, 3.seconds())?).get()
	return ok(message.data.decode_utf8() or "")
