import send, recv, read_to_end from "./support/conn.ms"
import expect_equal, expect_error, expect_false, expect_ok from "@std/test/test.ms"
import http_result from "./support/http.ms"
import HttpMethod from "@std/net/http.ms"
import text_headers, list_headers from "./support/http.ms"
import (
    parse_certificates,
    verify_certificates,
    CertificateInfo,
    TlsOptions
) from "@std/net/tls.ms"
import (HttpExchange, HttpServerOptions, HttpClientOptions) from "@std/net/http.ms"
import Bytes from "@std/bytes.ms"
import connect, http_client, listen, listen_tls, serve from "@std/net/net.ms"
import timestamp from "@std/os/time.ms"
import promise, wait_all from "@std/concurrency/promise.ms"
import Listener, Connection from "@std/net/net.ms"
import certificate, private_key from "./support/certificates.ms"

fn hello(var exchange: HttpExchange) Unit!:
    let _started = try exchange.send_headers(
        status: 200, headers: (try list_headers(Map[String, List[String]]()))
    )
    let _written = (try http_result(exchange.write("secure")))
    return ok(unit)

test "TLS certificate parsing verification hostname and expiration":
    let certificates = (
        parse_certificates(
            pem: certificate(), max_certificates: 1
        ) | try expect_ok
    )
    try expect_false(
        (
            certificates.length() != 1
            or certificates.get(0).dns_names != ["stdlib.test"]
        )
    )

    let now = (timestamp(seconds: 1893456000, nanoseconds: 0) | try expect_ok)
    let _verified = (
        verify_certificates(
            chain_pem: certificate(), roots_pem: certificate(),
            server_name: "stdlib.test", now: now
        ) | try expect_ok
    )
    let failed: Unit! = error(Error("TLS: authentication failed", kind: "EAUTH"))
    try expect_false(
        (
            verify_certificates(
                chain_pem: certificate(), roots_pem: certificate(),
                server_name: "wrong.test", now: now
            ) != failed
        )
    )

    let expired = (timestamp(seconds: 4133980800, nanoseconds: 0) | try expect_ok)
    try expect_false(
        (
            verify_certificates(
                chain_pem: certificate(), roots_pem: certificate(),
                server_name: "stdlib.test", now: expired
            ) != failed
        )
    )

test "TLS rejects malformed PEM and certificate budgets":
    let invalid: List[CertificateInfo]! = error(
        Error("TLS: invalid data", kind: "EBADMSG")
    )
    parse_certificates(pem: "not PEM") | try expect_equal(invalid)

    let limited: List[CertificateInfo]! = error(
        Error("TLS: limit exceeded", kind: "EOVERFLOW")
    )
    parse_certificates(pem: certificate(), max_certificates: 0) | try expect_equal(
        limited
    )

test "HTTPS trusts only the explicitly supplied local test root":
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: ["http/1.1"],
        require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        timeout: 3.seconds(), grace: 0.seconds(), tls: server_tls
    )
    let server = serve(address: "127.0.0.1:0", handler: hello, options: server_options) | try expect_ok
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: false
    )
    let client = http_client(
        HttpClientOptions(decompress: false, cookies: false, tls: client_tls)
    ) | try expect_ok
    var response = client.request(
        method: HttpMethod.Get, url: "https://{server.address()}/",
        headers: (try text_headers(Map[String, String]())), body: "",
        timeout: 2.seconds()
    ) | try expect_ok
    try expect_false(
        (
            response.metadata.status != 200
            or (
                read_to_end(var response.body) | try expect_ok
            ) != "secure".to_bytes()
        )
    )

fn report_protocol(var exchange: HttpExchange) Unit!:
    let _started = try exchange.send_headers(
        status: 200, headers: (try list_headers(Map[String, List[String]]()))
    )
    let _written = (try http_result(exchange.write(exchange.protocol())))
    return ok(unit)

test "HTTP/2 negotiates through ALPN and reports the protocol on both sides":
    let server_options = HttpServerOptions(
        timeout: 3.seconds(),
        grace: 0.seconds(),
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: ["h2", "http/1.1"],
            require_client_certificate: false
        )
    )
    let server = serve(
        address: "127.0.0.1:0", handler: report_protocol, options: server_options
    ) | try expect_ok
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["h2", "http/1.1"], require_client_certificate: false
    )
    let client = http_client(
        HttpClientOptions(decompress: false, cookies: false, tls: client_tls)
    ) | try expect_ok
    var response = client.request(
        method: HttpMethod.Get, url: "https://{server.address()}/",
        headers: (try text_headers(Map[String, String]())), body: "",
        timeout: 2.seconds()
    ) | try expect_ok
    try expect_equal(response.metadata.protocol, "HTTP/2.0")
    try expect_equal(try read_to_end(var response.body), "HTTP/2.0".to_bytes())

fn answer_ping(var connection: Connection) Int:
    let ping = recv(var connection, 3.seconds())
    let pong = send(var connection, "pong")
    connection.close().get(none)
    if ping.is_error() or pong.is_error():
        return 0

    return 1

fn serve_one_tls(listener: Listener) Int:
    match listener.accept(3.seconds()).wait():
        ok(accepted):
            var connection = accepted
            return answer_ping(var connection)
        error(_): return 0

test "raw TLS listeners and clients handshake and report negotiated details":
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: ["http/1.1"],
        require_client_certificate: false
    )
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: false
    )
    let listener = try listen_tls("127.0.0.1:0", server_tls, 3.seconds())
    let address = listener.address()
    let served = promise(fn: ok(serve_one_tls(listener)))
    var client = try connect(address.clone(), tls: client_tls, timeout: 3.seconds()).wait()
    try send(var client, "ping")
    try expect_equal((try recv(var client, 3.seconds())).get(), "pong".to_bytes())

    let info = try client.info.tls_info()
    try expect_false(info.version < 771)
    try expect_equal(info.alpn, "http/1.1")
    try expect_false(not info.verified)
    try expect_equal(info.peer_certificates.length(), 1)
    try expect_false(info.peer_certificates[0].length() < 100)

    var more = info.peer_certificates.clone()
    more.append(more[0].clone())
    try expect_equal(more.length(), 2)
    try expect_equal(more[1].length(), more[0].length())
    try client.close()
    try expect_equal((try wait_all([served]))[0], 1)

test "connect_tls trusts only the system roots and tls_info rejects plain TCP":
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: [], require_client_certificate: false
    )
    let listener = try listen_tls("127.0.0.1:0", server_tls, 3.seconds())
    let address = listener.address()
    let served = promise(fn: ok(serve_one_tls(listener)))
    let _failure = try expect_error(
        connect(
            address.clone(), tls: TlsOptions(server_name: "stdlib.test"),
            timeout: 3.seconds()
        ).wait()
    )
    let _served = try wait_all([served])
    let plain = try listen("127.0.0.1:0")
    var client = try connect(plain.address(), timeout: 2.seconds()).wait()
    try expect_false(client.info.tls_info().is_ok())

fn count_until_eof(listener: Listener) Int:
    var accepted = listener.accept(5.seconds()).wait()
    if accepted.is_error(): return -1

    var connection = accepted.get()
    var total = 0
    var reads = 0

    while reads < 100000:
        reads += 1

        let chunk = recv(var connection, 5.seconds())
        if chunk.is_error(): return -2
        if chunk.get().is_none(): break

        total += chunk.get().get(Bytes([])).length()

    connection.close().get(none)
    return total

test "raw TLS client that writes a large payload and closes at once loses no bytes":
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: [], require_client_certificate: false
    )
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: [], require_client_certificate: false
    )
    let listener = try listen_tls("127.0.0.1:0", server_tls, 5.seconds())
    let address = listener.address()
    let served = promise(fn: ok(count_until_eof(listener)))
    var client = try connect(address.clone(), tls: client_tls, timeout: 5.seconds()).wait()
    try send(var client, "y".repeat(20000000).get())

    // No read first: the server's post-handshake bytes must not reset the connection.
    try client.close()
    try expect_equal((try wait_all([served]))[0], 20000000)
