from "@std/testing.ms" import expect_ok
from "./support/http.ms" import http_result
from "@std/core.ms" import TextError
from "@std/http.ms" import headers, HttpMethod, buffered
from "./support/http.ms" import text_headers, list_headers
from "@std/http.ms" import (
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpServerOptions,
    HttpClientOptions,
    HttpHeaders
)
from "@std/net.ms" import network
from "@std/net.ms" import TlsOptions
from "@std/bytes.ms" import Bytes

def route(request: HttpRequest) -> HttpResponse:
    var cookies = Map[String, String]()
    cookies.add("Set-Cookie", "a=1")
    cookies.add("set-cookie", "b=2")

    let fields = match text_headers(cookies):
        case ok(found): found
        case error(cause): return HttpResponse(
            status: 500, headers: headers(), body: (cause.message().to_bytes())
        )

    return HttpResponse(
        status: 200, headers: fields, body: f"{request.path}|{request.query}".to_bytes()
    )

def stream_route(exchange: HttpExchange) -> Result[Unit, HttpError]:
    var chain_1 = Map[String, List[String]]()
    chain_1.add(key: "Set-Cookie", value: ["a=1", "b=2"])

    let _sent = try exchange.send_headers(
        status: 200, headers: (try list_headers(chain_1))
    )
    let _written = (
        try http_result(exchange.write(f"{exchange.path()}|{exchange.query()}"))
    )
    return ok(())

def check_route(url: String, expected: String) -> Result[Unit, Error]:
    let response = network().request(
        method: HttpMethod.Get, url: url,
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
    ) | try expect_ok
    if response.metadata().status != 200 or response.body != expected.to_bytes(): return error(
        TextError("path or raw query changed")
    )
    if (
        (
            response
            .metadata()
            .headers
            .text("SET-cookie") | try expect_ok
        ) != some(["a=1", "b=2"])
    ): return error(TextError("#257 repeated cookies regressed"))

    return ok(())

def check_rejected(url: String) -> Result[Unit, Error]:
    let response = network().request(
        method: HttpMethod.Get, url: url,
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
    ) | try expect_ok
    if response.metadata().status != 400: return error(
        TextError("unsafe or invalid path was dispatched")
    )

    return ok(())

def check_paths(base: String) -> Result[Unit, Error]:
    (try check_route(url: f"{base}/a%20b", expected: "/a b|"))
    (try check_route(url: f"{base}/%2e%2e/x?y=%2F", expected: "/x|y=%2F"))
    (try check_route(url: f"{base}/a/../b/", expected: "/b/|"))
    (try check_route(url: f"{base}/a%252Fb?x=%2500", expected: "/a%2Fb|x=%2500"))
    (try check_rejected(f"{base}/a%2Fb"))
    (try check_rejected(f"{base}/a%00b"))
    (try check_rejected(f"{base}/bad%ff/../x"))
    return ok(())

test "buffered routes validate original input and decode once":
    with let server = network().serve(address: "127.0.0.1:0", handler: buffered(route)) | try expect_ok:
        (try check_paths(f"http://{server.address()}"))

test "streaming routes validate original input and decode once":
    with let server = network().serve(
        address: "127.0.0.1:0", handler: stream_route,
        options: HttpServerOptions(tls: none)
    ) | try expect_ok:
        (try check_paths(f"http://{server.address()}"))

def expect_http_error[T](outcome: Result[T, HttpError]) -> Result[Unit, Error]:
    match outcome:
        case ok(_): return error(TextError("invalid URL succeeded"))
        case error(cause):
            if cause != HttpError.InvalidInput: return error(
                TextError("malformed URL leaked transport error")
            )

    return ok(())

test "buffered and reusable clients reject malformed ports as InvalidInput":
    let headers = (try text_headers(Map[String, String]()))
    let body = ""
    network().request(
        method: HttpMethod.Get, url: "http://127.0.0.1:99999/", headers: headers,
        body: body
    ) | try expect_http_error

    let tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: False
    )
    with let client = network().http_client(
        HttpClientOptions(decompress: False, cookies: False, tls: tls)
    ) | try expect_ok:
        client.request(
            method: HttpMethod.Get, url: "http://127.0.0.1:65536/", headers: headers,
            body: body
        ) | try expect_http_error
