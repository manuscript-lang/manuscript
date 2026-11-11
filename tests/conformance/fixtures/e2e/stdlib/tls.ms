// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	promise, wait_all from "@std/concurrency/promise.ms",
	HttpClientOptions,
	HttpExchange,
	HttpMethod,
	HttpServerOptions from "@std/net/http.ms",
	Connection,
	Listener,
	connect,
	http_client,
	listen,
	listen_tls,
	serve from "@std/net/net.ms",
	CertificateInfo,
	TlsOptions,
	parse_certificates,
	verify_certificates from "@std/net/tls.ms",
	expect_equal, expect_error, expect_false, expect_ok from "@std/test/test.ms",
	timestamp from "@std/time.ms",

	certificate, private_key from "./support/certificates.ms",
	read_to_end, recv, send from "./support/conn.ms",
	http_result, list_headers, text_headers from "./support/http.ms",
)

fn hello(var exchange: HttpExchange) Unit!:
	_started := exchange.send_headers(
		status: 200,
		headers: (list_headers(Map[String, List[String]]())?),
	)?
	_written := (http_result(exchange.write("secure"))?)

test "TLS certificate parsing verification hostname and expiration":
	certificates := (
		parse_certificates(pem: certificate(), max_certificates: 1) | expect_ok?
	)
	expect_false(
		(
			certificates.length() != 1
			or certificates.get(0).dns_names != ["stdlib.test"]
		)
	)?

	now := (timestamp(seconds: 1893456000, nanoseconds: 0) | expect_ok?)
	_verified := (
		verify_certificates(
			chain_pem: certificate(),
			roots_pem: certificate(),
			server_name: "stdlib.test",
			now: now,
		) | expect_ok?
	)
	failed: Unit! := error(Error("TLS: authentication failed", kind: "EAUTH"))
	expect_false(
		(
			verify_certificates(
				chain_pem: certificate(),
				roots_pem: certificate(),
				server_name: "wrong.test",
				now: now,
			) != failed
		)
	)?

	expired := (timestamp(seconds: 4133980800, nanoseconds: 0) | expect_ok?)
	expect_false(
		(
			verify_certificates(
				chain_pem: certificate(),
				roots_pem: certificate(),
				server_name: "stdlib.test",
				now: expired,
			) != failed
		)
	)?

test "TLS rejects malformed PEM and certificate budgets":
	invalid: List[CertificateInfo]! := error(
		Error("TLS: invalid data", kind: "EBADMSG")
	)
	parse_certificates(pem: "not PEM") | expect_equal(invalid)?

	limited: List[CertificateInfo]! := error(
		Error("TLS: limit exceeded", kind: "EOVERFLOW")
	)
	parse_certificates(pem: certificate(), max_certificates: 0) | expect_equal(limited)?

test "HTTPS trusts only the explicitly supplied local test root":
	server_tls := TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: certificate(),
		private_key_pem: private_key(),
		alpn: ["http/1.1"],
		require_client_certificate: false,
	)
	server_options := HttpServerOptions(
		timeout: 3.seconds(),
		grace: 0.seconds(),
		tls: server_tls,
	)
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: hello,
			options: server_options,
		) | expect_ok?
	)
	client_tls := TlsOptions(
		server_name: "stdlib.test",
		roots_pem: certificate(),
		certificate_pem: "",
		private_key_pem: "",
		alpn: ["http/1.1"],
		require_client_certificate: false,
	)
	client := (
		http_client(
			HttpClientOptions(
				decompress: false,
				cookies: false,
				tls: client_tls,
			)
		) | expect_ok?
	)
	var response = (
		client.request(
			method: HttpMethod.Get,
			url: "https://{server.address()}/",
			headers: (text_headers(Map[String, String]())?),
			body: "",
			timeout: 2.seconds(),
		)
		| expect_ok?
	)
	expect_false(
		(
			response.metadata.status != 200
			or (
				read_to_end(var response.body) | expect_ok?
			) != "secure".to_bytes()
		)
	)?

fn report_protocol(var exchange: HttpExchange) Unit!:
	_started := exchange.send_headers(
		status: 200,
		headers: (list_headers(Map[String, List[String]]())?),
	)?
	_written := (http_result(exchange.write(exchange.protocol()))?)

test "HTTP/2 negotiates through ALPN and reports the protocol on both sides":
	server_options := HttpServerOptions(
		timeout: 3.seconds(),
		grace: 0.seconds(),
		tls: TlsOptions(
			server_name: "",
			roots_pem: "",
			certificate_pem: certificate(),
			private_key_pem: private_key(),
			alpn: ["h2", "http/1.1"],
			require_client_certificate: false,
		),
	)
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: report_protocol,
			options: server_options,
		) | expect_ok?
	)
	client_tls := TlsOptions(
		server_name: "stdlib.test",
		roots_pem: certificate(),
		certificate_pem: "",
		private_key_pem: "",
		alpn: ["h2", "http/1.1"],
		require_client_certificate: false,
	)
	client := (
		http_client(
			HttpClientOptions(
				decompress: false,
				cookies: false,
				tls: client_tls,
			)
		) | expect_ok?
	)
	var response = (
		client.request(
			method: HttpMethod.Get,
			url: "https://{server.address()}/",
			headers: (text_headers(Map[String, String]())?),
			body: "",
			timeout: 2.seconds(),
		)
		| expect_ok?
	)
	expect_equal(response.metadata.protocol, "HTTP/2.0")?
	expect_equal(read_to_end(var response.body)?, "HTTP/2.0".to_bytes())?

fn answer_ping(var connection: Connection) Int:
	ping := recv(var connection, 3.seconds())
	pong := send(var connection, "pong")
	connection.close().get(none)
	if ping.is_error() or pong.is_error(): return 0

	return 1

fn serve_one_tls(listener: Listener) Int:
	match listener.accept(3.seconds()).wait():
		ok(accepted):
			var connection = accepted
			return answer_ping(var connection)
		error(_): return 0

test "raw TLS listeners and clients handshake and report negotiated details":
	server_tls := TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: certificate(),
		private_key_pem: private_key(),
		alpn: ["http/1.1"],
		require_client_certificate: false,
	)
	client_tls := TlsOptions(
		server_name: "stdlib.test",
		roots_pem: certificate(),
		certificate_pem: "",
		private_key_pem: "",
		alpn: ["http/1.1"],
		require_client_certificate: false,
	)
	listener := listen_tls("127.0.0.1:0", server_tls, 3.seconds())?
	address := listener.address()
	served := promise(fn: ok(serve_one_tls(listener)))
	var client = connect(address.clone(), tls: client_tls, timeout: 3.seconds()).wait()?
	send(var client, "ping")?
	expect_equal((recv(var client, 3.seconds())?).get(), "pong".to_bytes())?

	info := client.info.tls_info()?
	expect_false(info.version < 771)?
	expect_equal(info.alpn, "http/1.1")?
	expect_false(not info.verified)?
	expect_equal(info.peer_certificates.length(), 1)?
	expect_false(info.peer_certificates[0].length() < 100)?

	var more = info.peer_certificates.clone()
	more.append(more[0].clone())
	expect_equal(more.length(), 2)?
	expect_equal(more[1].length(), more[0].length())?
	client.close()?
	expect_equal((wait_all([served])?)[0], 1)?

test "connect_tls trusts only the system roots and tls_info rejects plain TCP":
	server_tls := TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: certificate(),
		private_key_pem: private_key(),
		alpn: [],
		require_client_certificate: false,
	)
	listener := listen_tls("127.0.0.1:0", server_tls, 3.seconds())?
	address := listener.address()
	served := promise(fn: ok(serve_one_tls(listener)))
	_failure := expect_error(
		connect(
			address.clone(),
			tls: TlsOptions(server_name: "stdlib.test"),
			timeout: 3.seconds(),
		).wait()
	)?
	_served := wait_all([served])?
	plain := listen("127.0.0.1:0")?
	var client = connect(plain.address(), timeout: 2.seconds()).wait()?
	expect_false(client.info.tls_info().is_ok())?

fn count_until_eof(listener: Listener) Int:
	var accepted = listener.accept(5.seconds()).wait()
	if accepted.is_error(): return -1

	var connection = accepted.get()
	var total = 0
	var reads = 0

	while reads < 100000:
		reads += 1

		chunk := recv(var connection, 5.seconds())
		if chunk.is_error(): return -2
		if chunk.get().is_none(): break

		total += chunk.get().get(Bytes([])).length()

	connection.close().get(none)
	return total

test "raw TLS client that writes a large payload and closes at once loses no bytes":
	server_tls := TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: certificate(),
		private_key_pem: private_key(),
		alpn: [],
		require_client_certificate: false,
	)
	client_tls := TlsOptions(
		server_name: "stdlib.test",
		roots_pem: certificate(),
		certificate_pem: "",
		private_key_pem: "",
		alpn: [],
		require_client_certificate: false,
	)
	listener := listen_tls("127.0.0.1:0", server_tls, 5.seconds())?
	address := listener.address()
	served := promise(fn: ok(count_until_eof(listener)))
	var client = connect(address.clone(), tls: client_tls, timeout: 5.seconds()).wait()?
	send(var client, "y".repeat(20000000).get())?

	// No read first: the server's post-handshake bytes must not reset the connection.
	client.close()?
	expect_equal((wait_all([served])?)[0], 20000000)?
