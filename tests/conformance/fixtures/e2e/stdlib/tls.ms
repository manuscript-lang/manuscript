// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	promise, wait_all from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	HttpClientOptions,
	HttpExchange,
	HttpMethod,
	HttpServerOptions from "@std/net/http.ms",
	Connection,
	Listener,
	accept_tls,
	connect,
	http_client,
	listen,
	listen_tls,
	serve,
	start_tls from "@std/net/net.ms",
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

fn hello(var exchange: HttpExchange) Void!:
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
	failed: Void! := error(Error("TLS: authentication failed", kind: "EAUTH"))
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
			url: f"https://{server.address()}/",
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
				read_to_end(response.body) | expect_ok?
			) != "secure".to_bytes()
		)
	)?

fn report_protocol(var exchange: HttpExchange) Void!:
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
			url: f"https://{server.address()}/",
			headers: (text_headers(Map[String, String]())?),
			body: "",
			timeout: 2.seconds(),
		)
		| expect_ok?
	)
	expect_equal(response.metadata.protocol, "HTTP/2.0")?
	expect_equal(read_to_end(response.body)?, "HTTP/2.0".to_bytes())?

fn answer_ping(move connection: Connection) Int:
	ping := recv(connection, 3.seconds())
	pong := send(connection, "pong")
	void connection.close()
	if ping.is_error() or pong.is_error(): return 0

	return 1

fn serve_one_tls(listener: Listener) Int:
	match listener.accept(3.seconds()).wait():
		ok(accepted):
			var connection = accepted
			return answer_ping(connection)
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
	send(client, "ping")?
	expect_equal(
		(recv(client, 3.seconds())?) or panic("called Optional.get() on null"),
		"pong".to_bytes(),
	)?

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

		chunk := recv(connection, 5.seconds())
		if chunk.is_error(): return -2
		if chunk.get() == null: break

		total += (chunk.get() or Bytes([])).length()

	void connection.close()
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
	send(client, "y".repeat(20000000))?

	// No read first: the server's post-handshake bytes must not reset the connection.
	client.close()?
	expect_equal((wait_all([served])?)[0], 20000000)?

fn starttls_server(listener: Listener, options: TlsOptions) Int:
	var plain = listener.accept(3.seconds()).wait().get()
	hello := recv(plain, 3.seconds())
	if hello.is_error(): return 0
	if (hello.get() or Bytes([])) != "STARTTLS".to_bytes(): return 0
	if send(plain, "OK").is_error(): return 0

	upgraded := accept_tls(plain, options, 3.seconds())
	if upgraded.is_error(): return 0

	secure := upgraded.get()
	return answer_ping(secure)

test "start_tls upgrades a plain connection in place on both sides":
	server_tls := TlsOptions(
		certificate_pem: certificate(),
		private_key_pem: private_key(),
	)
	client_tls := TlsOptions(server_name: "stdlib.test", roots_pem: certificate())
	listener := listen("127.0.0.1:0")?
	address := listener.address()
	served := promise(fn: ok(starttls_server(listener, server_tls)))
	var plain = connect(address.clone(), timeout: 3.seconds()).wait()?
	expect_false(plain.info.tls_info().is_ok())?
	send(plain, "STARTTLS")?
	expect_equal(
		(recv(plain, 3.seconds())?) or panic("called Optional.get() on null"),
		"OK".to_bytes(),
	)?

	var client = start_tls(plain, client_tls, 3.seconds())?
	expect_equal(client.info.peer_address, address)?

	info := client.info.tls_info()?
	expect_false(info.version < 771)?
	expect_false(not info.verified)?
	send(client, "ping")?
	expect_equal(
		(recv(client, 3.seconds())?) or panic("called Optional.get() on null"),
		"pong".to_bytes(),
	)?

	// The plain value was consumed.
	_late := expect_error(plain.output.write("late".to_bytes()))?

	// A TLS connection cannot be upgraded again.
	_again := expect_error(start_tls(client, client_tls, 3.seconds()))?
	client.close()?
	expect_equal((wait_all([served])?)[0], 1)?

test "start_tls rejects an untrusted server and an empty server name":
	server_tls := TlsOptions(
		certificate_pem: certificate(),
		private_key_pem: private_key(),
	)
	listener := listen("127.0.0.1:0")?
	address := listener.address()
	served := promise(fn: ok(starttls_server(listener, server_tls)))
	var plain = connect(address.clone(), timeout: 3.seconds()).wait()?
	_unnamed := expect_error(start_tls(plain, TlsOptions(), 3.seconds()))?
	send(plain, "STARTTLS")?
	expect_equal(
		(recv(plain, 3.seconds())?) or panic("called Optional.get() on null"),
		"OK".to_bytes(),
	)?

	_untrusted := expect_error(
		start_tls(plain, TlsOptions(server_name: "stdlib.test"), 3.seconds())
	)?
	_served := wait_all([served])?
