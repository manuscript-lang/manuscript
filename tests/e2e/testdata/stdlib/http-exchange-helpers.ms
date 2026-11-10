import (
    expect_equal from "@std/test/test.ms",
    buffered,
    headers,
    read_body,
    reply,
    text,
    HttpExchange,
    HttpMethod,
    HttpRequest,
    HttpResponse from "@std/net/http.ms",
    http_client, serve from "@std/net/net.ms",
)

fn echo(request: HttpRequest) HttpResponse:
    return text(201, "{request.path}:{request.body.decode_utf8().get("")}")

fn exchange_echo(var exchange: HttpExchange) Unit!:
    body := try read_body(var exchange, 8)
    return reply(var exchange, text(200, "{body.length()}"))

test "buffered adapts a request-to-response handler":
    server := try serve("127.0.0.1:0", buffered(echo))
    client := try http_client()
    var response = try client.request(
        HttpMethod.Post, "http://{server.address()}/x", headers(), "abc"
    )
    try expect_equal(response.metadata.status, 201)

    var text = ""
    for chunk in response.body:
        text += chunk.decode_utf8().get("")
    try expect_equal(text, "/x:abc")

test "read_body bounds the body by its limit":
    server := try serve("127.0.0.1:0", exchange_echo)
    client := try http_client()
    small := try client.request(
        HttpMethod.Post, "http://{server.address()}/", headers(), "12345"
    )
    try expect_equal(small.metadata.status, 200)

    large := try client.request(
        HttpMethod.Post, "http://{server.address()}/", headers(), "123456789"
    )
    try expect_equal(large.metadata.status, 500)

fn bare(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, body: "bare".to_bytes())

test "serve, the client and a response take their defaults":
    server := try serve("127.0.0.1:0", buffered(bare))
    client := try http_client()
    var response = try client.request(HttpMethod.Get, "http://{server.address()}/")
    try expect_equal(response.metadata.status, 200)

    var got = ""
    for chunk in response.body:
        got += chunk.decode_utf8().get("")
    try expect_equal(got, "bare")
