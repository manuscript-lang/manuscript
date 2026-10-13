import {
    header_values,
    HttpRequest,
    HttpResponse,
    HttpExchange,
    HttpError,
    HttpServerOptions
} from "@std/http.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import {List, Map} from "@std/collections.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn handle_headers(request: HttpRequest) -> HttpResponse:
    if request.header("content-type") != some("application/octet-stream".to_bytes()):
        return panic("case-insensitive request header")
    if request.header("CONTENT-TYPE") != request.header("Content-Type"):
        return panic("header spelling differs")
    if request.headers.get("content-type").is_some():
        return panic("raw Map keys changed")
    if request.headers.get("Content-Type") != request.header("content-type"):
        return panic("canonical Map key missing")

    return HttpResponse(
        status: 200,
        headers: (
            Map[String, String]()
            .with_entry(key: "x-dup", value: "first")
            .with_entry(key: "X-Dup", value: "second")
            .with_entry(
                key: "Set-Cookie",
                value: "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT"
            )
            .with_entry(key: "set-cookie", value: "b=2")
        ),
        body: "ok".to_bytes()
    )

test "buffered requests support case-insensitive header lookup":
    with server = value(
        network().serve(address: "127.0.0.1:0", handler: handle_headers)
    ):
        let response = value(
            network().request(
                method: "GET",
                url: "http://{server.address()}/",
                headers: Map[
                    String,
                    String
                ]().with_entry(key: "content-type", value: "application/octet-stream"),
                body: "".to_bytes()
            )
        )
        if response.status != 200: return panic("header handler failed")
        if response.headers.get("X-Dup") != some(["first", "second"]):
            return panic("case-colliding response values lost")
        if (
            response.headers.get("Set-Cookie") != some(
                [
                    "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT",
                    "b=2"
                ]
            )
        ):
            return panic("cookies combined or lost")
        if response.headers.get("x-dup").is_some():
            return panic("Map lookup changed")
        if (
            header_values(headers: response.headers, name: "x-DUP") != some(
                ["first", "second"]
            )
        ):
            return panic("case-insensitive response lookup lost values")

fn echo_buffered_headers(request: HttpRequest) -> HttpResponse:
    let raw = request.header("X-DUP").unwrap()
    let values = raw.to_text().unwrap().split("\n")
    if values != ["", "second"]: return panic("joined bytes bridge lost values")

    return HttpResponse(
        status: 200,
        headers: Map[String, String](),
        body: "ok".to_bytes()
    )

test "outbound collisions and buffered byte bridge retain empty fields":
    with server = value(
        network().serve(address: "127.0.0.1:0", handler: echo_buffered_headers)
    ):
        let response = value(
            network().request(
                method: "GET",
                url: "http://{server.address()}/",
                headers: (
                    Map[String, String]()
                    .with_entry(key: "x-dup", value: "")
                    .with_entry(key: "X-Dup", value: "second")
                ),
                body: "".to_bytes(),
                timeout: 2.seconds
            )
        )
        if response.status != 200: return panic("buffered bridge handler failed")

    if not Bytes(values: [255]).to_text().is_none(): return panic(
        "invalid UTF-8 converted to text"
    )

fn echo_streaming_headers(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let values = header_values(
        headers: exchange.headers(),
        name: "x-DUP"
    ).unwrap()
    return exchange.send_headers(
        status: 200,
        headers: Map[String, List[String]]().with_entry(
            key: "X-Dup",
            value: values
        )
    )

test "explicit server TLS absence and list bridge preserve streaming fields":
    with server = value(
        network().serve_stream(
            address: "127.0.0.1:0",
            handler: echo_streaming_headers,
            options: HttpServerOptions(tls: none)
        )
    ):
        let response = value(
            network().request(
                method: "GET",
                url: "http://{server.address()}/",
                headers: (
                    Map[String, String]()
                    .with_entry(key: "x-dup", value: "")
                    .with_entry(key: "X-Dup", value: "second")
                ),
                body: "".to_bytes(),
                timeout: 2.seconds
            )
        )
        if (
            response.status != 200
            or response.headers.get("X-Dup") != some(["", "second"])
        ):
            return panic("streaming list bridge lost fields")

    if not HttpServerOptions(tls: none).tls.is_none():
        return panic("explicit server TLS absence changed")

test "header lookup preserves empty and repeated values and map order":
    let headers = (
        Map[String, Bytes]()
        .with_entry(
            key: "x-test",
            value: "first\nsecond".to_bytes()
        )
        .with_entry(
            key: "X-Test",
            value: "later".to_bytes()
        )
        .with_entry(
            key: "X-Empty",
            value: "".to_bytes()
        )
    )
    let request = HttpRequest(
        method: "GET",
        path: "/",
        query: "",
        headers: headers,
        body: "".to_bytes()
    )
    let lookup = request.header
    if lookup("X-TEST") != some("first\nsecond".to_bytes()): return panic(
        "first matching key"
    )
    if request.header("x-empty") != some("".to_bytes()): return panic(
        "empty header is present"
    )
    if not request.header("missing").is_none(): return panic("missing header")
    if headers.get("X-Test") != some("later".to_bytes()): return panic(
        "lookup mutated Map"
    )

test "list-valued lookup combines equivalent keys and copies membership":
    let first = ["", "first"]
    let headers = (
        Map[String, List[String]]()
        .with_entry(key: "x-test", value: first)
        .with_entry(key: "X-Test", value: ["second", "third"])
        .with_entry(key: "X-Empty", value: [])
        .with_entry(key: "K", value: ["ascii"])
    )
    let lookup = header_values
    let combined = lookup(headers: headers, name: "X-TEST").unwrap()
    if combined != ["", "first", "second", "third"]: return panic(
        "values lost or reordered"
    )

    combined.append("copy")
    first.append("input")
    if combined != ["", "first", "second", "third", "copy"]: return panic(
        "input changed copy membership"
    )
    if first != ["", "first", "input"]: return panic("copy changed input membership")
    if headers.keys() != ["x-test", "X-Test", "X-Empty", "K"]: return panic(
        "lookup changed keys"
    )
    if header_values(headers: headers, name: "x-empty") != some(List[String]()): return panic(
        "present empty list became absent"
    )
    if not header_values(headers: headers, name: "missing").is_none(): return panic(
        "missing name present"
    )
    if not header_values(headers: headers, name: "K").is_none(): return panic(
        "Unicode fold used for an HTTP name"
    )
