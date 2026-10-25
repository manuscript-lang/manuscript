from "@std/testing.ms" import expect_equal
from "@std/http.ms" import buffered, headers, read_body, reply, text, HttpClientOptions, HttpError, HttpExchange, HttpMethod, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import read_all
from "@std/sse.ms" import body_stream
from "@std/net.ms" import network

def echo(request: HttpRequest) -> HttpResponse:
    return text(201, f"{request.path}:{request.body.decode_utf8().get("")}")

def exchange_echo(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let body = try read_body(exchange, 8)
    return reply(exchange, text(200, f"{body.length()}"))

test "buffered adapts a request-to-response handler":
    with let server = try network().serve_stream(
        "127.0.0.1:0", buffered(echo), HttpServerOptions()
    ):
        with let client = try network().http_client(HttpClientOptions()):
            let response = try client.request(
                HttpMethod.Post, f"http://{server.address()}/x", headers(), "abc"
            )
            try expect_equal(response.metadata().status, 201)

            let body = try read_all(body_stream(response))
            try expect_equal(body.decode_utf8().get(""), "/x:abc")

test "read_body bounds the body by its limit":
    with let server = try network().serve_stream(
        "127.0.0.1:0", exchange_echo, HttpServerOptions()
    ):
        with let client = try network().http_client(HttpClientOptions()):
            let small = try client.request(
                HttpMethod.Post, f"http://{server.address()}/", headers(), "12345"
            )
            try expect_equal(small.metadata().status, 200)

            let large = try client.request(
                HttpMethod.Post, f"http://{server.address()}/", headers(), "123456789"
            )
            try expect_equal(large.metadata().status, 500)
