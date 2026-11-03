import expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms"
import (
    HttpClientOptions,
    HttpExchange,
    HttpMethod,
    HttpServerOptions,
    HttpRequest,
    HttpResponse,
    buffered,
    headers
) from "@std/net/http.ms"
import TlsOptions, connect, http_client, serve from "@std/net/net.ms"
import text_headers from "./support/http.ms"
import certificate, private_key from "./support/certificates.ms"

fn plain_handler() fn(HttpExchange) Unit!:
    let tag = "hello"
    let handler = fn(request: HttpRequest) HttpResponse:
        return HttpResponse(status: 200, headers: headers(), body: tag.to_bytes())
    return buffered(handler)

fn get(address: String) String:
    var client = connect(address, 2.seconds).get()
    let _ = client.write("GET /x HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
    var text = ""

    while true:
        let chunk = client.read(none, 2.seconds)
        if chunk.is_error():
            break

        if let data = chunk.get(none):
            text = "{text}{data.decode_utf8().get("")}"
            continue

        break

    return text

test "serve answers many connections on several cores":
    let server = serve(
        "127.0.0.1:0", plain_handler(), HttpServerOptions(cores: 3)
    ) | try expect_ok

    for i in 0..9:
        let text = get(server.address())
        try expect_true(text.starts_with("HTTP/1.1 200 OK"))
        try expect_true(text.ends_with("hello"))

test "serve rejects fewer than one core":
    let refused = serve("127.0.0.1:0", plain_handler(), HttpServerOptions(cores: 0)) | try expect_error
    try expect_equal(refused.kind, ErrorCategory.InvalidInput)

test "close stops accepting and wait returns":
    var server = serve("127.0.0.1:0", plain_handler()) | try expect_ok
    let address = server.address()
    try expect_true(get(address).starts_with("HTTP/1.1 200 OK"))
    server.close().get(unit)
    try expect_ok(server.wait(timeout: 5.seconds))
    try expect_true(connect(address, 500.milliseconds).is_error())

fn secure_handler(exchange: HttpExchange) Unit!:
    let _ = try exchange.send_headers(status: 200, headers: headers())
    let _ = try exchange.write("secure")
    return ok(unit)

test "TLS connections are served on several cores":
    let server_tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: ["h2", "http/1.1"],
        require_client_certificate: false
    )
    let server = serve(
        "127.0.0.1:0",
        secure_handler,
        HttpServerOptions(timeout: 3.seconds, grace: 0.seconds, tls: server_tls, cores: 3)
    ) | try expect_ok

    for i in 0..9:
        let client_tls = TlsOptions(
            server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
            private_key_pem: "", alpn: ["http/1.1"], require_client_certificate: false
        )
        let client = http_client(
            HttpClientOptions(decompress: false, cookies: false, tls: client_tls)
        ) | try expect_ok
        let response = client.request(
            method: HttpMethod.Get, url: "https://{server.address()}/",
            headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
        ) | try expect_ok
        try expect_equal(response.metadata().status, 200)
