from "@std/http.ms" import HttpExchange, HttpError, HttpMethod, HttpServerOptions, HttpClientOptions, headers, Server, Router, text_response, Response, Body
from "@std/net.ms" import network, TlsOptions
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep
from "@std/testing.ms" import expect_equal, expect_true
from "./support/certificates.ms" import certificate, private_key

def sized(exchange: HttpExchange) -> Result[Unit, HttpError]:
    if exchange.path() == "/head-unknown": return exchange.send_headers(200, headers())
    if exchange.path() == "/reset": return exchange.send_headers(205, headers(), 0)
    if exchange.path() == "/not-modified": return exchange.send_headers(
        304, headers(), 123
    )
    if exchange.path() == "/bad-no-content": return exchange.send_headers(
        204, headers(), 0
    )

    try exchange.send_headers(200, headers(), 3)
    if exchange.method() == HttpMethod.Head: return ok(())

    let written = exchange.write("ab" if exchange.path() == "/short" else "abc")
    if written.is_error(): return error(HttpError.Failed(written.err().message()))

    return ok(())

test "declared lengths cover HTTP1 and HTTP2 including HEAD and bodyless statuses":
    let options = HttpServerOptions(
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: [], require_client_certificate: False
        )
    )

    with let server = try network().serve_stream("127.0.0.1:0", sized, options):
        for protocol in ["http/1.1", "h2"]:
            let tls = TlsOptions(
                server_name: "stdlib.test", roots_pem: certificate(),
                certificate_pem: "", private_key_pem: "", alpn: [protocol.clone()],
                require_client_certificate: False
            )

            with let client = try network().http_client(HttpClientOptions(tls: tls)):
                for path in ["/", "/reset", "/not-modified"]:
                    with let response = try client.request(
                        HttpMethod.Get, f"https://{server.address()}{path}", headers()
                    ):
                        let length = (
                            response
                            .metadata()
                            .headers
                            .text("Content-Length")
                            .get()
                            .get() [0]
                        )
                        try expect_equal(
                            length,
                            "3" if path == "/" else (
                                "0" if path == "/reset" else "123"
                            )
                        )

                with let response = try client.request(
                    HttpMethod.Head, f"https://{server.address()}/", headers()
                ):
                    try expect_equal(
                        response.metadata().headers.text(
                            "Content-Length"
                        ).get().get() [0],
                        "3"
                    )
                with let response = try client.request(
                    HttpMethod.Head, f"https://{server.address()}/head-unknown",
                    headers()
                ):
                    try expect_true(
                        response.metadata().headers.values(
                            "Content-Length"
                        ).is_none()
                    )

                with let response = try client.request(
                    HttpMethod.Get, f"https://{server.address()}/short", headers()
                ):
                    var failed = False

                    while True:
                        let chunk = response.read()

                        if chunk.is_error():
                            failed = True
                            break

                        if chunk.get().is_none(): break

                    try expect_true(failed)

test "buffered application HEAD uses the final representation length":
    let server = Server("127.0.0.1:0")
    let owner = server.clone()

    with let tasks = TaskGroup[Result[Unit, HttpError]]():
        let task = tasks.spawn(
            lambda channel:
                var routes = Router()
                routes.get("/", lambda request: text_response("hello"))
                return owner.run(routes)
        )

        while server.address().is_none(): sleep(1.milliseconds)

        let response = try network().request(
            HttpMethod.Head, f"http://{server.address().get()}/", headers()
        )
        try expect_equal(
            response.head.headers.text("Content-Length").get().get() [0], "5"
        )
        try expect_equal(response.body.length(), 0)
        server.close()

        let result = try task.result()
        let done = try result
