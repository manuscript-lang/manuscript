import {expect_ok} from "@std/testing.ms"
import http_result from "./support/http.ms"
import TextError from "@std/errors.ms"
import {headers, HttpMethod} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import {
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpServerOptions,
    HttpClientOptions,
    HttpHeaders
} from "@std/http.ms"
import network from "@std/net.ms"
import TlsOptions from "@std/tls.ms"
import Bytes from "@std/bytes.ms"

fn route(request: HttpRequest) HttpResponse:
    let fields = match text_headers(
        (
            Map[String, String]()
            .add("Set-Cookie", "a=1")
            .add("set-cookie", "b=2")
        )
    ):
        ok(found): found
        error(cause): return HttpResponse(
            status: 500,
            headers: headers(),
            body: (cause.message().to_bytes())
        )

    return HttpResponse(
        status: 200,
        headers: fields,
        body: "{request.path}|{request.query}".to_bytes()
    )

fn stream_route(exchange: HttpExchange) Result[Unit, HttpError]:
    let sent = try exchange.send_headers(
        status: 200,
        headers: (
            try list_headers(
                Map[String, List[String]]().add(
                    key: "Set-Cookie",
                    value: ["a=1", "b=2"]
                )
            )
        )
    )
    let written = (
        try http_result(exchange.write("{exchange.path()}|{exchange.query()}"))
    )
    return ok(unit)

fn check_route(url: String, expected: String) Result[Unit, Error]:
    let response = (
        network().request(
            method: HttpMethod.Get,
            url: url,
            headers: (try text_headers(Map[String, String]())),
            body: "",
            timeout: 2.seconds
        ) | try expect_ok
    )
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

    return ok(unit)

fn check_rejected(url: String) Result[Unit, Error]:
    let response = (
        network().request(
            method: HttpMethod.Get,
            url: url,
            headers: (try text_headers(Map[String, String]())),
            body: "",
            timeout: 2.seconds
        ) | try expect_ok
    )
    if response.metadata().status != 400: return error(
        TextError("unsafe or invalid path was dispatched")
    )

    return ok(unit)

fn check_paths(base: String) Result[Unit, Error]:
    (try check_route(url: "{base}/a%20b", expected: "/a b|"))
    (try check_route(url: "{base}/%2e%2e/x?y=%2F", expected: "/x|y=%2F"))
    (try check_route(url: "{base}/a/../b/", expected: "/b/|"))
    (try check_route(url: "{base}/a%252Fb?x=%2500", expected: "/a%2Fb|x=%2500"))
    (try check_rejected("{base}/a%2Fb"))
    (try check_rejected("{base}/a%00b"))
    (try check_rejected("{base}/bad%ff/../x"))
    return ok(unit)

test "buffered routes validate original input and decode once":
    with server = (
        network().serve(address: "127.0.0.1:0", handler: route) | try expect_ok
    ):
        (try check_paths("http://{server.address()}"))

test "streaming routes validate original input and decode once":
    with server = (
        network().serve_stream(
            address: "127.0.0.1:0",
            handler: stream_route,
            options: HttpServerOptions(tls: none)
        ) | try expect_ok
    ):
        (try check_paths("http://{server.address()}"))

fn expect_http_error[T](outcome: Result[T, HttpError]) Result[Unit, Error]:
    match outcome:
        ok(_): return error(TextError("invalid URL succeeded"))
        error(cause):
            if cause != HttpError.InvalidInput: return error(
                TextError("malformed URL leaked transport error")
            )

    return ok(unit)

test "buffered and reusable clients reject malformed ports as InvalidInput":
    let headers = (try text_headers(Map[String, String]()))
    let body = ""
    (
        network().request(
            method: HttpMethod.Get,
            url: "http://127.0.0.1:99999/",
            headers: headers,
            body: body
        ) | try expect_http_error
    )
    let tls = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )
    with client = (
        network().http_client(
            HttpClientOptions(decompress: false, cookies: false, tls: tls)
        ) | try expect_ok
    ):
        (
            client.request(
                method: HttpMethod.Get,
                url: "http://127.0.0.1:65536/",
                headers: headers,
                body: body
            ) | try expect_http_error
        )
