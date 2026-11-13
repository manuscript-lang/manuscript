// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	HttpClientOptions,
	HttpExchange,
	HttpMethod,
	HttpServerOptions,
	headers,
	upgrade from "@std/net/http.ms",
	RequestOptions,
	connect,
	http_client,
	request,
	serve,
	web_socket from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	WebSocketKind, WebSocketMessage, WebSocketOptions from "@std/net/websocket.ms",
	expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test/test.ms",
	sleep from "@std/time.ms",

	recv, send, within from "./support/conn.ms",
	http_result, list_headers, text_headers from "./support/http.ms",
)

fn tls_options() TlsOptions:
	return TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: "",
		private_key_pem: "",
		alpn: [],
		require_client_certificate: false,
	)

fn echo(var exchange: HttpExchange) Unit!:
	if exchange.path() == "/ws":
		var socket = (
			http_result(
				upgrade(
					var exchange,
					allowed_origins: [],
					subprotocols: ["echo"],
					max_message_bytes: 1024,
				)
			)?
		)
		message := (http_result(socket.input.next())?).get()
		_sent := (
			http_result(
				socket.output.write(
					WebSocketMessage(
						data: message.data,
						kind: message.kind,
					)
				)
			)?
		)
		socket.close().get(none)
		return ok(unit)

	var chain_1 = Map[String, List[String]]()
	chain_1.add(key: "X-Test", value: ["manuscript"])

	headers := (list_headers(chain_1)?)
	_started := exchange.send_headers(status: 201, headers: headers)?
	_written := (http_result(exchange.write("hello"))?)

test "HTTP buffered and streaming clients call a Manuscript handler":
	options := HttpServerOptions(
		max_requests: 4,
		timeout: 3.seconds(),
		grace: 0.seconds(),
		tls: none,
	)
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: echo,
			options: options,
		) | expect_ok?
	)
	url := "http://{server.address()}/"
	response := (
		request(
			method: HttpMethod.Get,
			url: url,
			options: RequestOptions(
				headers: (text_headers(Map[String, String]())?),
				timeout: 2.seconds(),
			),
		) | expect_ok?
	)
	expect_false(
		(
			response.metadata().status != 201
			or response.body != "hello".to_bytes()
		)
	)?
	response.metadata().headers.values("X-Test") | expect_equal(["manuscript"])?

	client_options := HttpClientOptions(
		decompress: true,
		cookies: true,
		tls: tls_options(),
	)
	var client = http_client(client_options) | expect_ok?
	var body = (
		client.request(
			method: HttpMethod.Get,
			url: url,
			headers: (text_headers(Map[String, String]())?),
			body: "",
			max_response_bytes: 5,
			timeout: 2.seconds(),
		)
		| expect_ok?
	)
	body.metadata.status | expect_equal(201)?
	(body.body.next() | expect_ok?).get() | expect_equal("hello".to_bytes())?
	((body.body.next() | expect_ok?).is_none()) | expect_true?
	client.close()?

	_limited: Unit! := error(Error("HTTP: limit exceeded", kind: "EOVERFLOW"))

	match request(
		method: HttpMethod.Get,
		url: url,
		options: RequestOptions(
			headers: (text_headers(Map[String, String]())?),
			max_bytes: 4,
			timeout: 2.seconds(),
		),
	):
		ok(_): return fail("HTTP output budget ignored")
		error(cause):
			expect_equal(cause, Error("network: limit exceeded", kind: "EOVERFLOW"))?

test "WebSocket negotiates a protocol and echoes a text frame":
	options := HttpServerOptions(timeout: 3.seconds(), grace: 0.seconds(), tls: none)
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: echo,
			options: options,
		) | expect_ok?
	)
	client_options := WebSocketOptions(
		headers: (text_headers(Map[String, String]())?),
		subprotocols: ["echo"],
		max_message_bytes: 1024,
		timeout: 2.seconds(),
		tls: tls_options(),
		compression: false,
	)
	var socket = (
		web_socket(
			url: "ws://{server.address()}/ws",
			options: client_options,
		) | expect_ok?
	)
	socket.subprotocol | expect_equal("echo")?

	_sent := (
		socket.output.write(
			WebSocketMessage(
				data: "é🙂".to_bytes(),
				kind: WebSocketKind.Text,
			)
		)
		| expect_ok?
	)
	message := (socket.input.next() | expect_ok?).get()
	(
		(
			message.kind != WebSocketKind.Text
			or message.data != "é🙂".to_bytes()
		) | expect_false?
	)

fn upgrade_status(address: String, version: String, extra: String) String!:
	var client = connect(address, timeout: 2.seconds()).wait()?
	key := "dGhlIHNhbXBsZSBub25jZQ=="
	request := (
		"GET /ws {version}\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
		+ "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n{extra}\r\n"
	)
	send(var client, request)?

	reply := (recv(var client, 2.seconds())?).get(Bytes([]))
	return ok(reply.decode_utf8().get("").split("\r\n").first().get(""))

test "WebSocket upgrades need HTTP/1.1 and one key":
	options := HttpServerOptions(timeout: 3.seconds(), grace: 0.seconds(), tls: none)
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: echo,
			options: options,
		) | expect_ok?
	)
	address := server.address()
	expect_equal(
		upgrade_status(address, "HTTP/1.1", "")?,
		"HTTP/1.1 101 Switching Protocols",
	)?
	expect_equal(upgrade_status(address, "HTTP/1.0", "")?, "HTTP/1.1 400 Bad Request")?
	expect_equal(
		upgrade_status(
			address,
			"HTTP/1.1",
			"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n",
		)?,
		"HTTP/1.1 400 Bad Request",
	)?

fn report_host(var exchange: HttpExchange) Unit!:
	hosts := exchange.headers().values("Host")
	_started := exchange.send_headers(status: 200, headers: headers())?
	_written := (http_result(exchange.write(hosts.join(",")))?)

test "HTTP streaming handlers see the Host request header":
	options := HttpServerOptions(
		max_requests: 2,
		timeout: 3.seconds(),
		grace: 0.seconds(),
		tls: none,
	)
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: report_host,
			options: options,
		) | expect_ok?
	)
	response := (
		request(
			method: HttpMethod.Get,
			url: "http://{server.address()}/",
			options: RequestOptions(
				headers: (text_headers(Map[String, String]())?),
				timeout: 2.seconds(),
			),
		) | expect_ok?
	)
	response.body | expect_equal(server.address().to_bytes())?

test "HTTP requests reject an empty method":
	match request(
		method: HttpMethod.Custom(value: ""),
		url: "http://127.0.0.1:1/",
		options: RequestOptions(
			headers: (text_headers(Map[String, String]())?),
			timeout: 1.seconds(),
		),
	):
		ok(_): return fail("empty method accepted")
		error(cause):
			expect_equal(cause, Error("network: invalid input", kind: "EINVAL"))?

fn silent(var exchange: HttpExchange) Unit!:
	var _socket = (
		http_result(
			upgrade(
				var exchange,
				allowed_origins: [],
				subprotocols: [],
				max_message_bytes: none,
			)
		)?
	)
	_ := sleep(30.seconds()).wait()

test "a WebSocket read cancelled by its timeout leaves the socket closable":
	server := serve(address: "127.0.0.1:0", handler: silent) | expect_ok?
	var socket = web_socket("ws://{server.address()}/") | expect_ok?
	expect_true(within(var socket.input, 50.milliseconds()).is_error())?
	socket.close() | expect_ok?

test "a promise cancelled while it owns a WebSocket closes it without ending the program":
	server := serve(address: "127.0.0.1:0", handler: silent) | expect_ok?
	var socket = web_socket("ws://{server.address()}/") | expect_ok?

	// The closure takes the socket; its close at the end of the cancelled task parks,
	// which a cancel still pending on that task used to turn into a process exit.
	read := promise(fn: socket.input.next()).with(
		options: PromiseOptions(timeout: 50.milliseconds())
	).wait()
	expect_true(read.is_error())?

fn direct(var exchange: HttpExchange) Unit!:
	var socket = http_result(
		exchange.upgrade(
			allowed_origins: [],
			subprotocols: [],
			max_message_bytes: none,
		)
	)?
	message := (http_result(socket.input.next())?).get()
	_sent := http_result(socket.output.write(message))?

test "HttpExchange.upgrade returns a WebSocket":
	server := serve(address: "127.0.0.1:0", handler: direct) | expect_ok?
	var socket = web_socket("ws://{server.address()}/") | expect_ok?
	_sent := (
		socket.output.write(
			WebSocketMessage(
				data: "hi".to_bytes(),
				kind: WebSocketKind.Text,
			)
		)
		| expect_ok?
	)
	message := (socket.input.next() | expect_ok?).get()
	message.data | expect_equal("hi".to_bytes())?
