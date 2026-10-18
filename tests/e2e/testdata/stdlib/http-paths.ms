import HttpMethod from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import {
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpServerOptions,
    HttpClientOptions
} from "@std/http.ms"
import network from "@std/net.ms"
import TlsOptions from "@std/tls.ms"
import panic from "@std/faults.ms"

fn route(request: HttpRequest) HttpResponse:
    return HttpResponse(
        200,
        text_headers(
            (
                Map[String, String]()
                .add("Set-Cookie", "a=1")
                .add("set-cookie", "b=2")
            )
        ),
        "{request.path}|{request.query}".to_bytes()
    )

fn stream_route(exchange: HttpExchange) Result[Unit, HttpError]:
    try exchange.send_headers(
        200,
        list_headers(
            Map[String, List[String]]().add("Set-Cookie", ["a=1", "b=2"])
        )
    )
    exchange.write("{exchange.path()}|{exchange.query()}").get()
    return ok(unit)

fn check_route(url: String, expected: String) Result[Unit, Error]:
    let response = try network().request(
        HttpMethod.Get,
        url,
        text_headers(Map[String, String]()),
        "",
        timeout: 2.seconds
    )
    if response.metadata().status != 200 or response.body != expected.to_bytes(): return panic(
        "path or raw query changed"
    )
    if ((try response.metadata().headers.text("SET-cookie")) != some(["a=1", "b=2"])): return panic(
        "#257 repeated cookies regressed"
    )

    return ok(unit)

fn check_rejected(url: String) Result[Unit, Error]:
    let response = try network().request(
        HttpMethod.Get,
        url,
        text_headers(Map[String, String]()),
        "",
        timeout: 2.seconds
    )
    if response.metadata().status != 400: return panic(
        "unsafe or invalid path was dispatched"
    )

    return ok(unit)

fn check_paths(base: String) Result[Unit, Error]:
    try check_route("{base}/a%20b", "/a b|")
    try check_route("{base}/%2e%2e/x?y=%2F", "/x|y=%2F")
    try check_route("{base}/a/../b/", "/b/|")
    try check_route("{base}/a%252Fb?x=%2500", "/a%2Fb|x=%2500")
    try check_rejected("{base}/a%2Fb")
    try check_rejected("{base}/a%00b")
    try check_rejected("{base}/bad%ff/../x")
    return ok(unit)

test "buffered routes validate original input and decode once":
    with server = try network().serve("127.0.0.1:0", route):
        try check_paths("http://{server.address()}")

test "streaming routes validate original input and decode once":
    with server = try network().serve_stream(
        "127.0.0.1:0",
        stream_route,
        HttpServerOptions(tls: none)
    ):
        try check_paths("http://{server.address()}")

fn expect_http_error[T](outcome: Result[T, HttpError]) Unit:
    if not outcome.is_error(): return panic("invalid URL succeeded")
    if outcome.err() != HttpError.InvalidInput: return panic(
        "malformed URL leaked transport error"
    )

test "buffered and reusable clients reject malformed ports as InvalidInput":
    let headers = text_headers(Map[String, String]())
    let body = ""
    expect_http_error(
        network().request(
            HttpMethod.Get,
            "http://127.0.0.1:99999/",
            headers,
            body
        )
    )
    let tls = TlsOptions("", "", "", "", [], require_client_certificate: false)
    with client = try network().http_client(
        HttpClientOptions(decompress: false, cookies: false, tls: tls)
    ):
        expect_http_error(
            client.request(
                HttpMethod.Get,
                "http://127.0.0.1:65536/",
                headers,
                body
            )
        )
