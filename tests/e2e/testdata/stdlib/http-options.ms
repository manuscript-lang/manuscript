from "@std/http.ms" import headers, HttpRequest, HttpResponse, HttpExchange, HttpError, HttpServerOptions, HttpClientOptions, HttpMethod
from "@std/net.ms" import network, TlsOptions
from "@std/testing.ms" import expect_equal, expect_true
from "@std/json.ms" import parse, stringify
from "@std/time.ms" import duration
from "./support/certificates.ms" import certificate, private_key

def buffered(request: HttpRequest) -> HttpResponse:
    return HttpResponse(200, headers(), request.protocol.to_bytes())

def streamed(exchange: HttpExchange) -> Result[Unit, HttpError]:
    try exchange.send_headers(200, headers())

    let result = exchange.write(exchange.protocol())
    if result.is_error(): return error(HttpError.Failed(result.err().message()))

    return ok(())

test "both server forms accept omitted and explicitly unlimited options":
    with try network().serve("127.0.0.1:0", buffered) as first:
        try expect_true(first.address().starts_with("127.0.0.1:"))
    with try network().serve_stream("127.0.0.1:0", streamed) as second:
        try expect_true(second.address().starts_with("127.0.0.1:"))

    let options = HttpServerOptions(
        max_requests: none, max_header_bytes: none, tls: none
    )
    with try network().serve("127.0.0.1:0", buffered, options) as third:
        try expect_true(third.address().starts_with("127.0.0.1:"))
    with try network().serve_stream("127.0.0.1:0", streamed, options) as fourth:
        try expect_true(fourth.address().starts_with("127.0.0.1:"))

test "both server forms reject invalid options with the same error":
    for options in [
        HttpServerOptions(max_requests: 0), HttpServerOptions(max_requests: -1),
        HttpServerOptions(max_header_bytes: 0), HttpServerOptions(max_body_bytes: -1),
        HttpServerOptions(max_response_bytes: -1),
        HttpServerOptions(timeout: duration(-1)), HttpServerOptions(grace: duration(-1))
    ]:
        let first = network().serve("127.0.0.1:0", buffered, options)
        try expect_equal(first.err(), HttpError.InvalidInput)

        let second = network().serve_stream("127.0.0.1:0", streamed, options)
        try expect_equal(second.err(), HttpError.InvalidInput)

test "server options including durations can cross a JSON bootstrap":
    let options = HttpServerOptions(
        max_requests: 7, timeout: 2.seconds, grace: 0.seconds
    )
    let decoded = try parse[HttpServerOptions](try stringify(options))
    try expect_equal(decoded.max_requests, some(7))
    try expect_equal(decoded.timeout, some(2.seconds))
    try expect_equal(decoded.grace, some(0.seconds))
    try expect_true(decoded.tls.is_none())

test "buffered TLS negotiates HTTP1 and HTTP2 with default server ALPN":
    let options = HttpServerOptions(
        grace: 0.seconds,
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: [], require_client_certificate: False
        )
    )

    with try network().serve("127.0.0.1:0", buffered, options) as server:
        for protocol in ["http/1.1", "h2"]:
            let tls = TlsOptions(
                server_name: "stdlib.test", roots_pem: certificate(),
                certificate_pem: "", private_key_pem: "", alpn: [protocol.clone()],
                require_client_certificate: False
            )

            with try network().http_client(HttpClientOptions(tls: tls)) as client:
                with try client.request(
                    HttpMethod.Get, f"https://{server.address()}/", headers()
                ) as response:
                    var expected = "HTTP/1.1"
                    if protocol == "h2": expected = "HTTP/2.0"
                    try expect_equal(response.metadata().protocol, expected)
                    try expect_equal((try response.read()).get(), expected.to_bytes())

test "streaming TLS negotiates HTTP1 and HTTP2 with default server ALPN":
    let options = HttpServerOptions(
        grace: 0.seconds,
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: [], require_client_certificate: False
        )
    )

    with try network().serve_stream("127.0.0.1:0", streamed, options) as server:
        for protocol in ["http/1.1", "h2"]:
            let tls = TlsOptions(
                server_name: "stdlib.test", roots_pem: certificate(),
                certificate_pem: "", private_key_pem: "", alpn: [protocol.clone()],
                require_client_certificate: False
            )

            with try network().http_client(HttpClientOptions(tls: tls)) as client:
                with try client.request(
                    HttpMethod.Get, f"https://{server.address()}/", headers()
                ) as response:
                    var expected = "HTTP/1.1"
                    if protocol == "h2": expected = "HTTP/2.0"
                    try expect_equal(response.metadata().protocol, expected)
                    try expect_equal((try response.read()).get(), expected.to_bytes())
