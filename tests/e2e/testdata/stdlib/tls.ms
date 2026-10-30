import {expect_equal, expect_error, expect_false, expect_ok} from "@std/test.ms"
import http_result from "./support/http.ms"
import {headers, HttpMethod, buffered} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import {parse_certificates, verify_certificates, CertificateInfo, TlsError, TlsOptions} from "@std/net.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import network from "@std/net.ms"
import timestamp from "@std/time.ms"
import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import {Listener, Connection} from "@std/net.ms"
import {certificate, private_key} from "./support/certificates.ms"

fn hello(exchange: HttpExchange) Result[Unit, HttpError]:
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
    let failed: Result[Unit, TlsError] = error(TlsError.AuthenticationFailed)
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
    let invalid: Result[List[CertificateInfo], TlsError] = error(TlsError.InvalidData)
    parse_certificates(pem: "not PEM") | try expect_equal(invalid)

    let limited: Result[List[CertificateInfo], TlsError] = error(TlsError.LimitExceeded)
    parse_certificates(pem: certificate(), max_certificates: 0) | try expect_equal(
        limited
    )

test "HTTPS trusts only the explicitly supplied local test root":
    let net = network()
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: ["http/1.1"],
        require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        timeout: 3.seconds, grace: 0.seconds, tls: server_tls
    )
    let server = net.serve(
        address: "127.0.0.1:0", handler: hello, options: server_options
    ) | try expect_ok
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: false
    )
    let client = net.http_client(
        HttpClientOptions(decompress: false, cookies: false, tls: client_tls)
    ) | try expect_ok
    let response = client.request(
        method: HttpMethod.Get, url: "https://{server.address()}/",
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
    ) | try expect_ok
    try expect_false(
        (
            response.metadata().status != 200
            or (
                response.read() | try expect_ok
            ).get() != "secure".to_bytes()
        )
    )

fn report_protocol(exchange: HttpExchange) Result[Unit, HttpError]:
    let _started = try exchange.send_headers(
        status: 200, headers: (try list_headers(Map[String, List[String]]()))
    )
    let _written = (try http_result(exchange.write(exchange.protocol())))
    return ok(unit)

test "HTTP/2 negotiates through ALPN and reports the protocol on both sides":
    let net = network()
    let server_options = HttpServerOptions(
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: ["h2", "http/1.1"],
            require_client_certificate: false
        )
    )
    let server = net.serve(
        address: "127.0.0.1:0", handler: report_protocol, options: server_options
    ) | try expect_ok
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["h2", "http/1.1"], require_client_certificate: false
    )
    let client = net.http_client(
        HttpClientOptions(decompress: false, cookies: false, tls: client_tls)
    ) | try expect_ok
    let response = client.request(
        method: HttpMethod.Get, url: "https://{server.address()}/",
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
    ) | try expect_ok
    try expect_equal(response.metadata().protocol, "HTTP/2.0")
    try expect_equal((try response.read()).get(), "HTTP/2.0".to_bytes())

fn answer_ping(var connection: Connection) Int:
    let ping = connection.read(some(4), some(3.seconds))
    let pong = connection.write("pong", some(3.seconds))
    connection.close()
    if ping.is_error() or pong.is_error():
        return 0

    return 1

fn serve_one_tls(listener: Lock[Listener]) Int:
    match listener.get().accept(some(3.seconds)):
        ok(accepted):
            var connection = accepted
            return answer_ping(var connection)
        error(_): return 0

test "raw TLS listeners and clients handshake and report negotiated details":
    let net = network()
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: ["http/1.1"],
        require_client_certificate: false
    )
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: false
    )
    let listener: Lock[Listener] = new_lock(
        try net.listen_tls("127.0.0.1:0", server_tls, some(3.seconds))
    )
    var group = TaskGroup[Int]()
    let handle = listener
    group.spawn(fn ch: serve_one_tls(handle))

    var client = try net.connect_tls_config(
        listener.get().address(), client_tls, some(3.seconds)
    )
    try client.write("ping", some(3.seconds))
    try expect_equal(
        (try client.read(some(4), some(3.seconds))).get(), "pong".to_bytes()
    )

    let info = try client.tls_info()
    try expect_false(info.version < 771)
    try expect_equal(info.alpn, "http/1.1")
    try expect_false(not info.verified)
    try expect_equal(info.peer_certificates.length(), 1)
    try expect_false(info.peer_certificates[0].length() < 100)

    var more = info.peer_certificates.clone()
    more.append(more[0].clone())
    try expect_equal(more.length(), 2)
    try expect_equal(more[1].length(), more[0].length())
    client.close()

    let served = try group.results()
    try expect_equal(served[0], 1)
    group.close()
    listener.get().close()

test "connect_tls trusts only the system roots and tls_info rejects plain TCP":
    let net = network()
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: [], require_client_certificate: false
    )
    let listener: Lock[Listener] = new_lock(
        try net.listen_tls("127.0.0.1:0", server_tls, some(3.seconds))
    )
    var group = TaskGroup[Int]()
    let handle = listener
    group.spawn(fn ch: serve_one_tls(handle))

    let _failure = try expect_error(
        net.connect_tls(
            listener.get().address(), "stdlib.test", some(3.seconds)
        )
    )
    let _served = try group.results()
    group.close()
    listener.get().close()

    let plain = try net.listen("127.0.0.1:0")
    let client = try net.connect(plain.address(), some(2.seconds))
    try expect_false(client.tls_info().is_ok())
