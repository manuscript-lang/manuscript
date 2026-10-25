# conform: tags=aliasing,control-flow,faults,interpolation,match,modules,optional,records,stdlib-bytes,stdlib-http,stdlib-net,stdlib-testing,strings,testing,tier-io,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/http-headers.ms
from "@std/testing.ms" import expect_equal, expect_false, expect_ok, expect_true, fail
from "@std/http.ms" import (
    buffered,
    headers,
    HttpHeaders,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpClientOptions,
    HttpServerOptions
)
from "@std/net.ms" import network
from "@std/bytes.ms" import Bytes

def repeated_headers() -> Result[HttpHeaders, Error]:
    let fields = headers()
    let first = (fields.append("x-dup", "first".to_bytes()) | try expect_ok)
    let second = (fields.append("X-Dup", "second".to_bytes()) | try expect_ok)
    let cookie = (
        fields.append(
            "Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT".to_bytes()
        ) | try expect_ok
    )
    let other = (fields.append("set-cookie", "b=2".to_bytes()) | try expect_ok)
    return ok(fields)

def header_failure(message: String) -> HttpResponse:
    return HttpResponse(status: 500, headers: headers(), body: message.to_bytes())

def handle_headers(request: HttpRequest) -> HttpResponse:
    if request.method != HttpMethod.Get: return header_failure("typed request method")

    let received = match request.headers.text("X-DUP"):
        case ok(found): found
        case error(cause): return header_failure(cause.message())

    if received != some(["first", "second"]): return header_failure(
        "case-insensitive received fields"
    )

    let fields = match repeated_headers():
        case ok(found): found
        case error(cause): return header_failure(cause.message())

    return HttpResponse(status: 200, headers: fields, body: "ok".to_bytes())

test "one header type preserves repeated values through buffered requests":
    with let server = (
        network().serve(
            address: "127.0.0.1:0", handler: buffered(handle_headers),
            options: HttpServerOptions(max_requests: 2)
        ) | try expect_ok
    ):
        let response = (
            network().request(
                method: HttpMethod.Get, url: f"http://{server.address()}/",
                headers: (try repeated_headers()), body: ""
            ) | try expect_ok
        )
        let metadata = response.metadata()
        metadata.status | try expect_equal(200)
        (
            metadata.headers.text(
                "x-dup"
            ) | try expect_ok | try expect_equal(some(["first", "second"]))
        )
        try expect_false(
            (
                (
                    metadata
                    .headers
                    .text("SET-COOKIE") | try expect_ok
                ) != some(["a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"])
            )
        )

        let appended = (
            (
                metadata
                .headers
                .append("x-dup", "third".to_bytes())
            ) | try expect_ok
        )
        try expect_false(
            (
                (
                    response
                    .metadata()
                    .headers
                    .text("X-Dup") | try expect_ok
                ) != some(["first", "second", "third"])
            )
        )

def echo_headers(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let received = exchange.headers()
    if (try received.text("X-DUP")) != some(["first", "second"]): return error(
        HttpError.InvalidData
    )

    let output = received.clone()
    let removed_connection = output.remove("Connection")
    let removed_length = output.remove("Content-Length")
    return exchange.send_headers(status: 200, headers: output)

test "streaming proxy uses the same byte-valued header type":
    with let server = (
        network().serve(
            address: "127.0.0.1:0", handler: echo_headers,
            options: HttpServerOptions(tls: none)
        ) | try expect_ok
    ):
        let response = (
            network().request(
                method: HttpMethod.Get, url: f"http://{server.address()}/",
                headers: (try repeated_headers()), body: ""
            ) | try expect_ok
        )
        try expect_false(
            (
                (
                    response
                    .metadata()
                    .headers
                    .text("x-DUP") | try expect_ok
                ) != some(["first", "second"])
            )
        )

test "lookup returns membership and clone separates it":
    let fields = (try repeated_headers())
    let appended = (fields.append("x-dup", "third".to_bytes()) | try expect_ok)
    let values = fields.values("X-DUP").get().clone()
    values.length() | try expect_equal(3)

    let copy = fields.clone()
    let copy_appended = (copy.append("x-dup", "copy".to_bytes()) | try expect_ok)
    fields.values("x-dup").get().length() | try expect_equal(3)
    (fields.values("missing").is_none()) | try expect_true

    let k = (fields.append("K", "ASCII".to_bytes()) | try expect_ok)
    (fields.values("K").is_none()) | try expect_true

    let removed = fields.remove("X-DUP")
    let new_field = (fields.append("X-Dup", "new".to_bytes()) | try expect_ok)
    (fields.values("x-dup").get().length() != 1) | try expect_false

test "explicit text extraction fails with typed UTF8 error":
    let fields = headers()
    let valid = (fields.append("Raw", "first".to_bytes()) | try expect_ok)
    let invalid = (fields.append("raw", Bytes(values: [255])) | try expect_ok)

    match fields.text("RAW"):
        case ok(_): return fail("invalid UTF8 accepted")
        case error(cause):
            try expect_equal(cause, HttpError.InvalidData)

    match fields.append("bad name", "value".to_bytes()):
        case ok(_): return fail("malformed name accepted")
        case error(cause):
            try expect_equal(cause, HttpError.InvalidInput)

test "empty options and an omitted request body use checked defaults":
    let client_options = HttpClientOptions()
    (client_options.decompress or client_options.cookies) | try expect_false
    (HttpServerOptions().tls.is_none()) | try expect_true
    with let server = (
        network().serve(
            address: "127.0.0.1:0", handler: echo_headers, options: HttpServerOptions()
        ) | try expect_ok
    ):
        with let client = (
            network().http_client(
                options: HttpClientOptions()
            ) | try expect_ok
        ):
            with let response = (
                client.request(
                    method: HttpMethod.Get, url: f"http://{server.address()}/",
                    headers: (try repeated_headers())
                ) | try expect_ok
            ):
                response.metadata().status | try expect_equal(200)
