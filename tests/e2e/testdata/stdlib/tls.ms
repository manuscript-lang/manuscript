import {HttpMethod} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import {parse_certificates, verify_certificates, CertificateInfo, TlsError, TlsOptions} from "@std/tls.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import network from "@std/net.ms"
import timestamp from "@std/time.ms"
import panic from "@std/faults.ms"
import {certificate, private_key} from "./support/certificates.ms"

fn hello(exchange: HttpExchange) Result[Unit, HttpError]:
    try exchange.send_headers(200, list_headers(Map[String, List[String]]()))
    exchange.write("secure".to_bytes()).unwrap()
    return ok(unit)

test "TLS certificate parsing verification hostname and expiration":
    let certificates = try parse_certificates(certificate(), 1)
    if (
        certificates.length() != 1
        or certificates.at(0).unwrap().dns_names != ["stdlib.test"]
    ): return panic("certificate metadata")

    let now = try timestamp(1893456000, 0)
    try verify_certificates(certificate(), certificate(), "stdlib.test", now)
    let failed: Result[Unit, TlsError] = error(TlsError.AuthenticationFailed)
    if (verify_certificates(certificate(), certificate(), "wrong.test", now) != failed): return panic(
        "hostname validation"
    )

    let expired = try timestamp(4133980800, 0)
    if (
        verify_certificates(
            certificate(),
            certificate(),
            "stdlib.test",
            expired
        ) != failed
    ): return panic("expiration validation")

test "TLS rejects malformed PEM and certificate budgets":
    let invalid: Result[List[CertificateInfo], TlsError] = error(TlsError.InvalidData)
    if parse_certificates("not PEM") != invalid: return panic("malformed PEM")

    let limited: Result[List[CertificateInfo], TlsError] = error(TlsError.LimitExceeded)
    if (parse_certificates(certificate(), 0) != limited): return panic(
        "certificate budget"
    )

test "HTTPS trusts only the explicitly supplied local test root":
    let net = network()
    let server_tls = TlsOptions(
        "",
        "",
        certificate(),
        private_key(),
        ["http/1.1"],
        require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: server_tls
    )

    with server = try net.serve_stream("127.0.0.1:0", hello, server_options):
        let client_tls = TlsOptions(
            "stdlib.test",
            certificate(),
            "",
            "",
            ["http/1.1"],
            require_client_certificate: false
        )
        with client = try net.http_client(
            HttpClientOptions(
                decompress: false,
                cookies: false,
                tls: client_tls
            )
        ):
            with response = try client.request(
                HttpMethod.Get,
                "https://{server.address()}/",
                text_headers(Map[String, String]()),
                "".to_bytes(),
                timeout: 2.seconds
            ):
                if (
                    response.metadata().status != 200
                    or (
                        try response.read()
                    ).unwrap() != "secure".to_bytes()
                ): return panic("HTTPS response")
