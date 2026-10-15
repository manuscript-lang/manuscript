import {headers, HttpMethod} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import {
    parse_certificates,
    verify_certificates,
    CertificateInfo,
    TlsError,
    TlsOptions
} from "@std/tls.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import network from "@std/net.ms"
import timestamp from "@std/time.ms"
import panic from "@std/faults.ms"
import {certificate, private_key} from "./support/certificates.ms"
import value from "./support/results.ms"

fn hello(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let started = value(
        exchange.send_headers(
            status: 200,
            headers: list_headers(Map[String, List[String]]())
        )
    )
    let written = value(exchange.write("secure".to_bytes()))
    return ok(unit)

test "TLS certificate parsing verification hostname and expiration":
    let certificates = value(
        parse_certificates(pem: certificate(), max_certificates: 1)
    )
    if (
        certificates.length != 1
        or certificates.at(0).unwrap().dns_names != ["stdlib.test"]
    ): return panic("certificate metadata")

    let now = value(timestamp(seconds: 1893456000, nanoseconds: 0))
    let verified = value(
        verify_certificates(
            chain_pem: certificate(),
            roots_pem: certificate(),
            server_name: "stdlib.test",
            now: now
        )
    )
    let failed: Result[Unit, TlsError] = error(TlsError.AuthenticationFailed)
    if (
        verify_certificates(
            chain_pem: certificate(),
            roots_pem: certificate(),
            server_name: "wrong.test",
            now: now
        ) != failed
    ): return panic("hostname validation")

    let expired = value(timestamp(seconds: 4133980800, nanoseconds: 0))
    if (
        verify_certificates(
            chain_pem: certificate(),
            roots_pem: certificate(),
            server_name: "stdlib.test",
            now: expired
        ) != failed
    ): return panic("expiration validation")

test "TLS rejects malformed PEM and certificate budgets":
    let invalid: Result[List[CertificateInfo], TlsError] = error(TlsError.InvalidData)
    if parse_certificates(pem: "not PEM") != invalid: return panic("malformed PEM")

    let limited: Result[List[CertificateInfo], TlsError] = error(TlsError.LimitExceeded)
    if (parse_certificates(pem: certificate(), max_certificates: 0) != limited): return panic(
        "certificate budget"
    )

test "HTTPS trusts only the explicitly supplied local test root":
    let net = network()
    let server_tls = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: certificate(),
        private_key_pem: private_key(),
        alpn: ["http/1.1"],
        require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: server_tls
    )

    with server = value(
        net.serve_stream(
            address: "127.0.0.1:0",
            handler: hello,
            options: server_options
        )
    ):
        let client_tls = TlsOptions(
            server_name: "stdlib.test",
            roots_pem: certificate(),
            certificate_pem: "",
            private_key_pem: "",
            alpn: ["http/1.1"],
            require_client_certificate: false
        )

        with client = value(
            net.http_client(
                HttpClientOptions(
                    decompress: false,
                    cookies: false,
                    tls: client_tls
                )
            )
        ):
            with response = value(
                client.request(
                    method: HttpMethod.Get,
                    url: "https://{server.address}/",
                    headers: text_headers(Map[String, String]()),
                    body: "".to_bytes(),
                    timeout: 2.seconds
                )
            ):
                if (
                    response.metadata.status != 200
                    or value(
                        response.read()
                    ).unwrap() != "secure".to_bytes()
                ): return panic("HTTPS response")
