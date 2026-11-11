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
		server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
		alpn: [], require_client_certificate: false
	)

fn echo(var exchange: HttpExchange) Unit!:
	if exchange.path() == "/ws":
		var socket = (
			try http_result(
				upgrade(
					var exchange, allowed_origins: [], subprotocols: ["echo"],
					max_message_bytes: 1024
				)
			)
		)
		message := (try http_result(socket.input.next())).get()
		_sent := (
			try http_result(
				socket.output.write(
					WebSocketMessage(
						data: message.data, kind: message.kind
					)
				)
			)
		)
		socket.close().get(none)
		return ok(unit)

	var chain_1 = Map[String, List[String]]()
	chain_1.add(key: "X-Test", value: ["manuscript"])

	headers := (try list_headers(chain_1))
	_started := try exchange.send_headers(status: 201, headers: headers)
	_written := (try http_result(exchange.write("hello")))

test "HTTP buffered and streaming clients call a Manuscript handler":
	options := HttpServerOptions(
		max_requests: 4, timeout: 3.seconds(), grace: 0.seconds(), tls: none
	)
	server := serve(address: "127.0.0.1:0", handler: echo, options: options) | try expect_ok
	url := "http://{server.address()}/"
	response := request(
		method: HttpMethod.Get,
		url: url,
		options: RequestOptions(
			headers: (try text_headers(Map[String, String]())), timeout: 2.seconds()
		)
	) | try expect_ok
	try expect_false(
		(
			response.metadata().status != 201
			or response.body != "hello".to_bytes()
		)
	)
	response.metadata().headers.values("X-Test") | try expect_equal(["manuscript"])

	client_options := HttpClientOptions(
		decompress: true, cookies: true, tls: tls_options()
	)
	var client = http_client(client_options) | try expect_ok
	var body = client.request(
		method: HttpMethod.Get, url: url,
		headers: (try text_headers(Map[String, String]())), body: "",
		max_response_bytes: 5, timeout: 2.seconds()
	) | try expect_ok
	body.metadata.status | try expect_equal(201)
	(body.body.next() | try expect_ok).get() | try expect_equal("hello".to_bytes())
	((body.body.next() | try expect_ok).is_none()) | try expect_true
	try client.close()

	_limited: Unit! := error(Error("HTTP: limit exceeded", kind: "EOVERFLOW"))

	match request(
		method: HttpMethod.Get,
		url: url,
		options: RequestOptions(
			headers: (try text_headers(Map[String, String]())), max_bytes: 4,
			timeout: 2.seconds()
		)
	):
		ok(_): return fail("HTTP output budget ignored")
		error(cause):
			try expect_equal(cause, Error("network: limit exceeded", kind: "EOVERFLOW"))

test "WebSocket negotiates a protocol and echoes a text frame":
	options := HttpServerOptions(timeout: 3.seconds(), grace: 0.seconds(), tls: none)
	server := serve(address: "127.0.0.1:0", handler: echo, options: options) | try expect_ok
	client_options := WebSocketOptions(
		headers: (try text_headers(Map[String, String]())), subprotocols: ["echo"],
		max_message_bytes: 1024, timeout: 2.seconds(), tls: tls_options(),
		compression: false
	)
	var socket = web_socket(url: "ws://{server.address()}/ws", options: client_options) | try expect_ok
	socket.subprotocol | try expect_equal("echo")

	_sent := socket.output.write(
		WebSocketMessage(data: "é🙂".to_bytes(), kind: WebSocketKind.Text)
	) | try expect_ok
	message := (socket.input.next() | try expect_ok).get()
	(message.kind != WebSocketKind.Text or message.data != "é🙂".to_bytes()) | try expect_false

fn upgrade_status(address: String, version: String, extra: String) String!:
	var client = try connect(address, timeout: 2.seconds()).wait()
	key := "dGhlIHNhbXBsZSBub25jZQ=="
	request := (
		"GET /ws {version}\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
		+ "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n{extra}\r\n"
	)
	try send(var client, request)

	reply := (try recv(var client, 2.seconds())).get(Bytes([]))
	return ok(reply.decode_utf8().get("").split("\r\n").first().get(""))

test "WebSocket upgrades need HTTP/1.1 and one key":
	options := HttpServerOptions(timeout: 3.seconds(), grace: 0.seconds(), tls: none)
	server := serve(address: "127.0.0.1:0", handler: echo, options: options) | try expect_ok
	address := server.address()
	try expect_equal(
		try upgrade_status(address, "HTTP/1.1", ""), "HTTP/1.1 101 Switching Protocols"
	)
	try expect_equal(
		try upgrade_status(address, "HTTP/1.0", ""), "HTTP/1.1 400 Bad Request"
	)
	try expect_equal(
		try upgrade_status(
			address, "HTTP/1.1", "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
		),
		"HTTP/1.1 400 Bad Request"
	)

fn report_host(var exchange: HttpExchange) Unit!:
	hosts := exchange.headers().values("Host")
	_started := try exchange.send_headers(status: 200, headers: headers())
	_written := (try http_result(exchange.write(hosts.join(","))))

test "HTTP streaming handlers see the Host request header":
	options := HttpServerOptions(
		max_requests: 2, timeout: 3.seconds(), grace: 0.seconds(), tls: none
	)
	server := serve(address: "127.0.0.1:0", handler: report_host, options: options) | try expect_ok
	response := request(
		method: HttpMethod.Get,
		url: "http://{server.address()}/",
		options: RequestOptions(
			headers: (try text_headers(Map[String, String]())), timeout: 2.seconds()
		)
	) | try expect_ok
	response.body | try expect_equal(server.address().to_bytes())

test "HTTP requests reject an empty method":
	match request(
		method: HttpMethod.Custom(value: ""),
		url: "http://127.0.0.1:1/",
		options: RequestOptions(
			headers: (try text_headers(Map[String, String]())), timeout: 1.seconds()
		)
	):
		ok(_): return fail("empty method accepted")
		error(cause):
			try expect_equal(cause, Error("network: invalid input", kind: "EINVAL"))

fn silent(var exchange: HttpExchange) Unit!:
	var _socket = (
		try http_result(
			upgrade(
				var exchange, allowed_origins: [], subprotocols: [],
				max_message_bytes: none
			)
		)
	)
	_ := sleep(30.seconds()).wait()

test "a WebSocket read cancelled by its timeout leaves the socket closable":
	server := serve(address: "127.0.0.1:0", handler: silent) | try expect_ok
	var socket = web_socket("ws://{server.address()}/") | try expect_ok
	try expect_true(within(var socket.input, 50.milliseconds()).is_error())
	socket.close() | try expect_ok

test "a promise cancelled while it owns a WebSocket closes it without ending the program":
	server := serve(address: "127.0.0.1:0", handler: silent) | try expect_ok
	var socket = web_socket("ws://{server.address()}/") | try expect_ok

	// The closure takes the socket; its close at the end of the cancelled task parks, which a
	// cancel still pending on that task used to turn into a process exit.
	read := promise(fn: socket.input.next()).with(
		options: PromiseOptions(timeout: 50.milliseconds())
	).wait()
	try expect_true(read.is_error())
