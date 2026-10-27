from "@std/test.ms" import expect_equal, expect_false, expect_ok
from "./support/http.ms" import http_result
from "@std/http.ms" import headers, HttpMethod, buffered
from "./support/http.ms" import text_headers, list_headers
from "@std/net.ms" import parse_certificates, verify_certificates, CertificateInfo, TlsError, TlsOptions
from "@std/http.ms" import HttpExchange, HttpError, HttpServerOptions, HttpClientOptions
from "@std/net.ms" import network
from "@std/time.ms" import timestamp
from "@std/shared.ms" import Shared, share
from "@std/tasks.ms" import TaskGroup
from "@std/net.ms" import Listener, Connection
from "./support/certificates.ms" import certificate, private_key

def hello(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let _started = try exchange.send_headers(
        status: 200, headers: (try list_headers(Map[String, List[String]]()))
    )
    let _written = (try http_result(exchange.write("secure")))
    return ok(())

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
        require_client_certificate: False
    )
    let server_options = HttpServerOptions(
        timeout: 3.seconds, grace: 0.seconds, tls: server_tls
    )

    with let server = net.serve(
        address: "127.0.0.1:0", handler: hello, options: server_options
    ) | try expect_ok:
        let client_tls = TlsOptions(
            server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
            private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: False
        )
        with let client = net.http_client(
            HttpClientOptions(
                decompress: False, cookies: False, tls: client_tls
            )
        ) | try expect_ok:
            with let response = client.request(
                method: HttpMethod.Get, url: f"https://{server.address()}/",
                headers: (try text_headers(Map[String, String]())), body: "",
                timeout: 2.seconds
            ) | try expect_ok:
                try expect_false(
                    (
                        response.metadata().status != 200
                        or (
                            response.read() | try expect_ok
                        ).get() != "secure".to_bytes()
                    )
                )

def report_protocol(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let _started = try exchange.send_headers(
        status: 200, headers: (try list_headers(Map[String, List[String]]()))
    )
    let _written = (try http_result(exchange.write(exchange.protocol())))
    return ok(())

test "HTTP/2 negotiates through ALPN and reports the protocol on both sides":
    let net = network()
    let server_options = HttpServerOptions(
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: ["h2", "http/1.1"],
            require_client_certificate: False
        )
    )

    with let server = net.serve(
        address: "127.0.0.1:0", handler: report_protocol, options: server_options
    ) | try expect_ok:
        let client_tls = TlsOptions(
            server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
            private_key_pem: "", alpn: ["h2", "http/1.1"],
            require_client_certificate: False
        )

        with let client = net.http_client(
            HttpClientOptions(
                decompress: False, cookies: False, tls: client_tls
            )
        ) | try expect_ok:
            with let response = client.request(
                method: HttpMethod.Get, url: f"https://{server.address()}/",
                headers: (try text_headers(Map[String, String]())), body: "",
                timeout: 2.seconds
            ) | try expect_ok:
                try expect_equal(response.metadata().protocol, "HTTP/2.0")
                try expect_equal((try response.read()).get(), "HTTP/2.0".to_bytes())

def answer_ping(connection: Connection) -> Int:
    let ping = connection.read(some(4), some(3.seconds))
    let pong = connection.write("pong", some(3.seconds))
    connection.close()
    if ping.is_error() or pong.is_error():
        return 0

    return 1

def serve_one_tls(listener: Shared[Listener]) -> Int:
    match listener.get().accept(some(3.seconds)):
        case ok(connection): return answer_ping(connection)
        case error(_): return 0

test "raw TLS listeners and clients handshake and report negotiated details":
    let net = network()
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: ["http/1.1"],
        require_client_certificate: False
    )
    let client_tls = TlsOptions(
        server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
        private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: False
    )
    let listener: Shared[Listener] = share(
        try net.listen_tls("127.0.0.1:0", server_tls, some(3.seconds))
    )

    with let group = TaskGroup[Int]():
        let handle = listener
        group.spawn(lambda ch: serve_one_tls(handle))

        with let client = try net.connect_tls_config(
            listener.get().address(), client_tls, some(3.seconds)
        ):
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

        let served = try group.results()
        try expect_equal(served[0], 1)

    listener.get().close()

test "connect_tls trusts only the system roots and tls_info rejects plain TCP":
    let net = network()
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: [], require_client_certificate: False
    )
    let listener: Shared[Listener] = share(
        try net.listen_tls("127.0.0.1:0", server_tls, some(3.seconds))
    )

    with let group = TaskGroup[Int]():
        let handle = listener
        group.spawn(lambda ch: serve_one_tls(handle))

        let refused = net.connect_tls(
            listener.get().address(), "stdlib.test", some(3.seconds)
        )
        try expect_false(refused.is_ok())

        let _served = try group.results()

    listener.get().close()
    with let plain = try net.listen("127.0.0.1:0"):
        with let client = try net.connect(plain.address(), some(2.seconds)):
            try expect_false(client.tls_info().is_ok())
