import expect_equal from "@std/test/test.ms"
import (
    buffered,
    headers,
    read_body,
    reply,
    text,
    HttpClientOptions,
    HttpExchange,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    HttpServerOptions
) from "@std/net/http.ms"
import read_all from "@std/io/io.ms"
import body_stream from "@std/net/sse.ms"
import http_client, serve from "@std/net/net.ms"

fn echo(request: HttpRequest) HttpResponse:
    return text(201, "{request.path}:{request.body.decode_utf8().get("")}")

fn exchange_echo(exchange: HttpExchange) Unit!:
    let body = try read_body(exchange, 8)
    return reply(exchange, text(200, "{body.length()}"))

test "buffered adapts a request-to-response handler":
    let server = try serve("127.0.0.1:0", buffered(echo), HttpServerOptions())
    let client = try http_client(HttpClientOptions())
    let response = try client.request(
        HttpMethod.Post, "http://{server.address()}/x", headers(), "abc"
    )
    try expect_equal(response.metadata().status, 201)

    let body = try read_all(body_stream(response))
    try expect_equal(body.decode_utf8().get(""), "/x:abc")

test "read_body bounds the body by its limit":
    let server = try serve("127.0.0.1:0", exchange_echo, HttpServerOptions())
    let client = try http_client(HttpClientOptions())
    let small = try client.request(
        HttpMethod.Post, "http://{server.address()}/", headers(), "12345"
    )
    try expect_equal(small.metadata().status, 200)

    let large = try client.request(
        HttpMethod.Post, "http://{server.address()}/", headers(), "123456789"
    )
    try expect_equal(large.metadata().status, 500)
