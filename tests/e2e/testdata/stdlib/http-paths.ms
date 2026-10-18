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
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn route(request: HttpRequest) -> HttpResponse:
    return HttpResponse(
        status: 200,
        headers: (
            text_headers(
                (
                    Map[String, String]()
                    .add(key: "Set-Cookie", value: "a=1")
                    .add(key: "set-cookie", value: "b=2")
                )
            )
        ),
        body: "{request.path}|{request.query}".to_bytes()
    )

fn stream_route(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let sent = try exchange.send_headers(
        status: 200,
        headers: list_headers(
            Map[String, List[String]]().add(
                key: "Set-Cookie",
                value: ["a=1", "b=2"]
            )
        )
    )
    let written = value(
        exchange.write("{exchange.path()}|{exchange.query()}".to_bytes())
    )
    return ok(unit)

fn check_route(url: String, expected: String) -> Unit:
    let response = value(
        network().request(
            method: HttpMethod.Get,
            url: url,
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            timeout: 2.seconds
        )
    )
    if response.metadata().status != 200 or response.body != expected.to_bytes(): return panic(
        "path or raw query changed"
    )
    if (value(response.metadata().headers.text("SET-cookie")) != some(["a=1", "b=2"])): return panic(
        "#257 repeated cookies regressed"
    )

fn check_rejected(url: String) -> Unit:
    let response = value(
        network().request(
            method: HttpMethod.Get,
            url: url,
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            timeout: 2.seconds
        )
    )
    if response.metadata().status != 400: return panic(
        "unsafe or invalid path was dispatched"
    )

fn check_paths(base: String) -> Unit:
    check_route(url: "{base}/a%20b", expected: "/a b|")
    check_route(url: "{base}/%2e%2e/x?y=%2F", expected: "/x|y=%2F")
    check_route(url: "{base}/a/../b/", expected: "/b/|")
    check_route(url: "{base}/a%252Fb?x=%2500", expected: "/a%2Fb|x=%2500")
    check_rejected("{base}/a%2Fb")
    check_rejected("{base}/a%00b")
    check_rejected("{base}/bad%ff/../x")

test "buffered routes validate original input and decode once":
    with server = value(network().serve(address: "127.0.0.1:0", handler: route)):
        check_paths("http://{server.address()}")

test "streaming routes validate original input and decode once":
    with server = value(
        network().serve_stream(
            address: "127.0.0.1:0",
            handler: stream_route,
            options: HttpServerOptions(tls: none)
        )
    ):
        check_paths("http://{server.address()}")

fn expect_http_error[T](outcome: Result[T, HttpError]) -> Unit:
    match outcome:
    ok(_): return panic("invalid URL succeeded")
    error(cause):
        if cause != HttpError.InvalidInput: return panic(
            "malformed URL leaked transport error"
        )

test "buffered and reusable clients reject malformed ports as InvalidInput":
    let headers = text_headers(Map[String, String]())
    let body = "".to_bytes()
    expect_http_error(
        network().request(
            method: HttpMethod.Get,
            url: "http://127.0.0.1:99999/",
            headers: headers,
            body: body
        )
    )
    let tls = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )
    with client = value(
        network().http_client(
            HttpClientOptions(decompress: false, cookies: false, tls: tls)
        )
    ):
        expect_http_error(
            client.request(
                method: HttpMethod.Get,
                url: "http://127.0.0.1:65536/",
                headers: headers,
                body: body
            )
        )
