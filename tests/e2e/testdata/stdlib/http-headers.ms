import {
    headers,
    HttpHeaders,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpClientOptions,
    HttpServerOptions
} from "@std/http.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import expect_error from "@std/testing.ms"

fn repeated_headers() Result[HttpHeaders, HttpError]:
    let fields = headers()
    try fields.append("x-dup", "first".to_bytes())
    try fields.append("X-Dup", "second".to_bytes())
    try fields.append(
        "Set-Cookie",
        "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT".to_bytes()
    )
    try fields.append("set-cookie", "b=2".to_bytes())
    return ok(fields)

fn handle_headers(request: HttpRequest) HttpResponse:
    if request.method != HttpMethod.Get: return panic("typed request method")
    if request.headers.text("X-DUP").get() != some(["first", "second"]): return panic(
        "case-insensitive received fields"
    )

    return HttpResponse(200, repeated_headers().get(), "ok".to_bytes())

test "one header type preserves repeated values through buffered requests":
    with server = try network().serve("127.0.0.1:0", handle_headers, 2):
        let response = try network().request(
            HttpMethod.Get,
            "http://{server.address()}/",
            try repeated_headers(),
            ""
        )
        let metadata = response.metadata()
        if metadata.status != 200: return panic("metadata status")
        if (try metadata.headers.text("x-dup")) != some(["first", "second"]): return panic(
            "response repeats lost"
        )
        if (
            (try metadata.headers.text("SET-COOKIE")) != some(
                ["a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"]
            )
        ): return panic("cookies combined or lost")

        try metadata.headers.append("x-dup", "third".to_bytes())
        if (
            (try response.metadata().headers.text("X-Dup")) != some(
                ["first", "second", "third"]
            )
        ): return panic("metadata copied header object")

fn echo_headers(exchange: HttpExchange) Result[Unit, HttpError]:
    let received = exchange.headers()
    if (try received.text("X-DUP")) != some(["first", "second"]): return error(
        HttpError.InvalidData
    )

    let output = received.clone()
    output.remove("Connection")
    output.remove("Content-Length")
    return exchange.send_headers(200, output)

test "streaming proxy uses the same byte-valued header type":
    with server = try network().serve_stream(
        "127.0.0.1:0",
        echo_headers,
        HttpServerOptions(tls: none)
    ):
        let response = try network().request(
            HttpMethod.Get,
            "http://{server.address()}/",
            try repeated_headers(),
            ""
        )
        if (
            (try response.metadata().headers.text("x-DUP")) != some(
                ["first", "second"]
            )
        ): return panic("stream proxy lost fields")

test "lookup shares mutable membership and clone separates it":
    let fields = try repeated_headers()
    let values = fields.values("X-DUP").get()
    try fields.append("x-dup", "third".to_bytes())
    if values.length() != 3: return panic("lookup copied membership")

    values.set(0, "changed".to_bytes())
    if fields.values("x-dup").get().at(0) != some("changed".to_bytes()): return panic(
        "list mutation not shared"
    )

    let copy = fields.clone()
    let copied_values = copy.values("x-dup").get()
    copied_values.set(0, "copy".to_bytes())
    if fields.values("x-dup").get().at(0) != some("changed".to_bytes()): return panic(
        "clone shared membership"
    )
    if not fields.values("missing").is_none(): return panic("absent header")

    try fields.append("K", "ASCII".to_bytes())
    if not fields.values("K").is_none(): return panic("Unicode folding")

    fields.remove("X-DUP")
    try fields.append("X-Dup", "new".to_bytes())
    if values.length() != 3 or fields.values("x-dup").get().length() != 1: return panic(
        "removed list alias reattached"
    )

test "explicit text extraction fails with typed UTF8 error":
    let fields = headers()
    try fields.append("Raw", "first".to_bytes())
    try fields.append("raw", Bytes([255]))
    if (try expect_error(fields.text("RAW"))) != HttpError.InvalidData: return panic(
        "wrong UTF8 error"
    )
    if (
        (
            try expect_error(fields.append("bad name", "value".to_bytes()))
        ) != HttpError.InvalidInput
    ): return panic("wrong name error")

test "empty options and an omitted request body use checked defaults":
    let client_options = HttpClientOptions()
    if client_options.decompress or client_options.cookies: return panic(
        "client Bool defaults changed"
    )
    if not HttpServerOptions().tls.is_none(): return panic("server TLS default changed")

    with server = try network().serve_stream(
        "127.0.0.1:0",
        echo_headers,
        HttpServerOptions()
    ):
        with client = try network().http_client(HttpClientOptions()):
            with response = try client.request(
                HttpMethod.Get,
                "http://{server.address()}/",
                try repeated_headers()
            ):
                if response.metadata().status != 200: return panic(
                    "plain request failed"
                )
