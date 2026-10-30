# conform: tags=aliasing,control-flow,faults,interpolation,match,modules,optional,records,stdlib-bytes,stdlib-http,stdlib-net,stdlib-testing,strings,testing,tier-io,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/http-headers.ms
import expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test.ms"
import (
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
) from "@std/http.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"

fn repeated_headers() Result[HttpHeaders, Error]:
    let fields = headers()
    let _first = fields.append("x-dup", "first") | try expect_ok
    let _second = fields.append("X-Dup", "second") | try expect_ok
    let _cookie = fields.append(
        "Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT"
    ) | try expect_ok
    let _other = fields.append("set-cookie", "b=2") | try expect_ok
    return ok(fields)

fn header_failure(message: String) HttpResponse:
    return HttpResponse(status: 500, headers: headers(), body: message.to_bytes())

fn handle_headers(request: HttpRequest) HttpResponse:
    if request.method != HttpMethod.Get: return header_failure("typed request method")

    let received = request.headers.values("X-DUP")
    if received != ["first", "second"]: return header_failure(
        "case-insensitive received fields"
    )

    let fields = match repeated_headers():
        ok(found): found
        error(cause): return header_failure(cause.message())

    return HttpResponse(status: 200, headers: fields, body: "ok".to_bytes())

test "one header type preserves repeated values through buffered requests":
    let server = network().serve(
        address: "127.0.0.1:0", handler: buffered(handle_headers),
        options: HttpServerOptions(max_requests: 2)
    ) | try expect_ok
    let response = network().request(
        method: HttpMethod.Get, url: "http://{server.address()}/",
        headers: (try repeated_headers()), body: ""
    ) | try expect_ok
    let metadata = response.metadata()
    metadata.status | try expect_equal(200)
    metadata.headers.values("x-dup") | try expect_equal(["first", "second"])
    try expect_false(
        (
            (metadata.headers.values("SET-COOKIE")) != [
                "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"
            ]
        )
    )

    let _appended = ((metadata.headers.append("x-dup", "third")) | try expect_ok)
    try expect_false(
        (
            (response.metadata().headers.values("X-Dup")) != [
                "first", "second", "third"
            ]
        )
    )

fn echo_headers(exchange: HttpExchange) Result[Unit, HttpError]:
    let received = exchange.headers()
    if received.values("X-DUP") != ["first", "second"]: return error(
        HttpError.InvalidData
    )

    let output = received.clone()
    let _removed_connection = output.remove("Connection")
    let _removed_length = output.remove("Content-Length")
    return exchange.send_headers(status: 200, headers: output)

test "streaming proxy uses the same byte-valued header type":
    let server = network().serve(
        address: "127.0.0.1:0", handler: echo_headers,
        options: HttpServerOptions(tls: none)
    ) | try expect_ok
    let response = network().request(
        method: HttpMethod.Get, url: "http://{server.address()}/",
        headers: (try repeated_headers()), body: ""
    ) | try expect_ok
    try expect_false(
        ((response.metadata().headers.values("x-DUP")) != ["first", "second"])
    )

test "lookup returns membership and clone separates it":
    let fields = (try repeated_headers())
    let _appended = fields.append("x-dup", "third") | try expect_ok
    let values = fields.values("X-DUP")
    values.length() | try expect_equal(3)

    let copy = fields.clone()
    let _copy_appended = copy.append("x-dup", "copy") | try expect_ok
    fields.values("x-dup").length() | try expect_equal(3)
    (not fields.contains("missing")) | try expect_true

    let _k = fields.append("K", "ASCII") | try expect_ok
    (not fields.contains("K")) | try expect_true

    let _removed = fields.remove("X-DUP")
    let _new_field = fields.append("X-Dup", "new") | try expect_ok
    (fields.values("x-dup").length() != 1) | try expect_false

test "string lookup leaves out values that are not UTF-8":
    let fields = headers()
    let _valid = fields.append("Raw", "first") | try expect_ok
    let _invalid = fields.append_bytes("raw", Bytes(values: [255])) | try expect_ok
    fields.values("RAW") | try expect_equal(["first"])
    fields.values_bytes("RAW").get().length() | try expect_equal(2)

    match fields.append("bad name", "value"):
        ok(_): return fail("malformed name accepted")
        error(cause):
            try expect_equal(cause, HttpError.InvalidInput)

test "empty options and an omitted request body use checked defaults":
    let client_options = HttpClientOptions()
    (client_options.decompress or client_options.cookies) | try expect_false
    (HttpServerOptions().tls.is_none()) | try expect_true

    let server = network().serve(
        address: "127.0.0.1:0", handler: echo_headers, options: HttpServerOptions()
    ) | try expect_ok
    let client = network().http_client(options: HttpClientOptions()) | try expect_ok
    let response = client.request(
        method: HttpMethod.Get, url: "http://{server.address()}/",
        headers: (try repeated_headers())
    ) | try expect_ok
    response.metadata().status | try expect_equal(200)
