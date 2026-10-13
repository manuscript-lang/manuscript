import {HttpRequest, HttpResponse} from "@std/http.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import Map from "@std/collections.ms"
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
        headers: Map[String, String](),
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
