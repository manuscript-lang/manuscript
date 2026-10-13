import {
    headers,
    HttpHeaders,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpServerOptions
} from "@std/http.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn repeated_headers() -> HttpHeaders:
    let fields = headers()
    let first = value(
        fields.append(
            "x-dup",
            "first".to_bytes()
        )
    )
    let second = value(
        fields.append(
            "X-Dup",
            "second".to_bytes()
        )
    )
    let cookie = value(
        fields.append(
            "Set-Cookie",
            "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT".to_bytes()
        )
    )
    let other = value(
        fields.append(
            "set-cookie",
            "b=2".to_bytes()
        )
    )
    return fields

fn handle_headers(request: HttpRequest) -> HttpResponse:
    if request.method != HttpMethod.Get: return panic("typed request method")
    if value(request.headers.text("X-DUP")) != some(["first", "second"]): return panic(
        "case-insensitive received fields"
    )

    return HttpResponse(
        status: 200,
        headers: repeated_headers(),
        body: "ok".to_bytes()
    )

test "one header type preserves repeated values through buffered requests":
    with server = value(
        network().serve(
            address: "127.0.0.1:0",
            handler: handle_headers,
            max_requests: 2
        )
    ):
        let response = value(
            network().request(
                method: HttpMethod.Get,
                url: "http://{server.address()}/",
                headers: repeated_headers(),
                body: "".to_bytes()
            )
        )
        let metadata = response.metadata()
        if metadata.status != 200: return panic("metadata status")
        if value(metadata.headers.text("x-dup")) != some(["first", "second"]): return panic(
            "response repeats lost"
        )
        if (
            value(metadata.headers.text("SET-COOKIE")) != some(
                ["a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"]
            )
        ): return panic("cookies combined or lost")

        let appended = value(
            metadata.headers.append(
                "x-dup",
                "third".to_bytes()
            )
        )
        if (
            value(response.metadata().headers.text("X-Dup")) != some(
                ["first", "second", "third"]
            )
        ): return panic("metadata copied header object")

fn echo_headers(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let received = exchange.headers()
    if value(received.text("X-DUP")) != some(["first", "second"]): return error(
        HttpError.InvalidData
    )

    let output = received.clone()
    let removed_connection = output.remove("Connection")
    let removed_length = output.remove("Content-Length")
    return exchange.send_headers(status: 200, headers: output)

test "streaming proxy uses the same byte-valued header type":
    with server = value(
        network().serve_stream(
            address: "127.0.0.1:0",
            handler: echo_headers,
            options: HttpServerOptions(tls: none)
        )
    ):
        let response = value(
            network().request(
                method: HttpMethod.Get,
                url: "http://{server.address()}/",
                headers: repeated_headers(),
                body: "".to_bytes()
            )
        )
        if (
            value(response.metadata().headers.text("x-DUP")) != some(
                ["first", "second"]
            )
        ): return panic("stream proxy lost fields")

test "lookup shares mutable membership and clone separates it":
    let fields = repeated_headers()
    let values = fields.values("X-DUP").unwrap()
    let appended = value(
        fields.append(
            "x-dup",
            "third".to_bytes()
        )
    )
    if values.length() != 3: return panic("lookup copied membership")

    let changed = values.set(
        0,
        "changed".to_bytes()
    )
    if fields.values("x-dup").unwrap().at(0) != some("changed".to_bytes()): return panic(
        "list mutation not shared"
    )

    let copy = fields.clone()
    let copied_values = copy.values("x-dup").unwrap()
    let copied_changed = copied_values.set(
        0,
        "copy".to_bytes()
    )
    if fields.values("x-dup").unwrap().at(0) != some("changed".to_bytes()): return panic(
        "clone shared membership"
    )
    if not fields.values("missing").is_none(): return panic("absent header")

    let k = value(
        fields.append(
            "K",
            "ASCII".to_bytes()
        )
    )
    if not fields.values("K").is_none(): return panic("Unicode folding")

    let removed = fields.remove("X-DUP")
    let new_field = value(
        fields.append(
            "X-Dup",
            "new".to_bytes()
        )
    )
    if values.length() != 3 or fields.values("x-dup").unwrap().length() != 1: return panic(
        "removed list alias reattached"
    )

test "explicit text extraction fails with typed UTF8 error":
    let fields = headers()
    let valid = value(
        fields.append(
            "Raw",
            "first".to_bytes()
        )
    )
    let invalid = value(
        fields.append(
            "raw",
            Bytes(values: [255])
        )
    )

    match fields.text("RAW"):
        ok(_): return panic("invalid UTF8 accepted")
        error(cause):
            if cause != HttpError.InvalidData: return panic("wrong UTF8 error")

    match fields.append(
        "bad name",
        "value".to_bytes()
    ):
        ok(_): return panic("malformed name accepted")
        error(cause):
            if cause != HttpError.InvalidInput: return panic("wrong name error")
