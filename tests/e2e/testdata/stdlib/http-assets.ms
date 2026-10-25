from "@std/sync.ms" import lock
from "@std/web_assets.ms" import asset, asset_response, Assets
from "@std/web_dates.ms" import http_date, parse_http_date
from "@std/http.ms" import Request, Response, Body, HttpMethod, headers
from "@std/time.ms" import timestamp
from "@std/testing.ms" import expect_equal, expect_true
from "@std/io.ms" import WriteStream, IoError
from "@std/shared.ms" import Shared, share
from "@std/bytes.ms" import Bytes

def text(response: Response) -> String:
    match response.body:
        case Buffered(data): return data.decode_utf8().get()
        case _: return ""

type Sink:
    bytes: Shared[Bytes]

impl WriteStream for Sink:
    var def close() -> Unit: return ()

    var def flush() -> Result[Unit, IoError]: return ok(())

    var def write(data: String) -> Result[Unit, IoError]: return self.write_bytes(
        data.to_bytes()
    )

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        with var guard = lock(self.bytes):
            guard.value = guard.value.concat(data)
        return ok(())

test "HTTP dates round trip current and obsolete forms with calendar validation":
    let time = try timestamp(784111777, 0)
    try expect_equal(try http_date(time), "Sun, 06 Nov 1994 08:49:37 GMT")
    for value in [
        "Sun, 06 Nov 1994 08:49:37 GMT", "Sunday, 06-Nov-94 08:49:37 GMT",
        "Sun Nov  6 08:49:37 1994"
    ]:
        try expect_equal(
            parse_http_date(value, time).get().unix_seconds(), time.unix_seconds()
        )
    try expect_true(parse_http_date("Sun, 31 Feb 1994 08:49:37 GMT").is_none())
    try expect_true(parse_http_date("Sun, 06 Nov 1994 08:49:37 PST").is_none())

test "asset validators precede byte ranges and preserve representation metadata":
    let time = try timestamp(784111777, 0)
    let value = try asset("0123456789".to_bytes(), "text/plain", some(time))
    let fields = headers()
    try fields.append("If-None-Match", ("W/" + value.etag).to_bytes())
    try fields.append("Range", "bytes=999-".to_bytes())

    let conditional = asset_response(Request(headers: fields), value)
    try expect_equal(conditional.status, 304)
    try expect_equal(conditional.content_length, some(10))
    try expect_equal(text(conditional), "")
    fields.remove("If-None-Match")
    try fields.append("If-Match", "\"different\"".to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 412)
    fields.remove("If-Match")
    fields.remove("Range")
    try fields.append("If-Modified-Since", (try http_date(time)).to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 304)
    try fields.append("If-None-Match", "\"different\"".to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 200)

test "assets serve bounded single suffix and multipart ranges":
    let value = try asset("0123456789".to_bytes(), "text/plain")
    let fields = headers()
    try fields.append("Range", "bytes=2-4".to_bytes())

    let part = asset_response(Request(headers: fields), value)
    try expect_equal(part.status, 206)
    try expect_equal(text(part), "234")
    try expect_equal(part.headers.text("Content-Range").get().get() [0], "bytes 2-4/10")
    fields.remove("Range")
    try fields.append("Range", "bytes=-3".to_bytes())
    try expect_equal(text(asset_response(Request(headers: fields), value)), "789")
    fields.remove("Range")
    try fields.append("Range", "bytes=0-1,8-9".to_bytes())

    let multiple = asset_response(Request(headers: fields), value)
    try expect_equal(multiple.status, 206)

    let output = share("".to_bytes())

    match multiple.body:
        case Stream(produce): try produce(Sink(output))
        case _: try expect_true(False)

    let payload = output.get().decode_utf8().get()
    try expect_true(payload.contains("Content-Range: bytes 0-1/10\r\n\r\n01\r\n"))
    try expect_true(payload.contains("Content-Range: bytes 8-9/10\r\n\r\n89\r\n"))
    try expect_equal(asset_response(Request(headers: fields), value, 1).status, 416)
    try expect_equal(
        asset_response(
            Request(method: HttpMethod.Head, headers: fields), value
        ).status,
        200
    )
    try fields.append("If-Range", "W/\"different\"".to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 200)

test "asset manifest serves exact registered paths without filesystem path joining":
    var files = Assets()
    try files.add("/public/app.js", try asset("ok".to_bytes(), "text/javascript"))
    try expect_equal(text(files.handle(Request(path: "/public/app.js"))), "ok")
    try expect_equal(files.handle(Request(path: "/private/secret")).status, 404)
    try expect_true(files.add("/../secret", try asset("bad".to_bytes())).is_error())
    try expect_equal(
        files.handle(
            Request(method: HttpMethod.Post, path: "/public/app.js")
        ).status,
        405
    )

test "If-Range requires exact dates and invalid duplicate fields fall back to full responses":
    let time = try timestamp(784111777, 0)
    let value = try asset("0123456789".to_bytes(), modified: some(time))
    let fields = headers()
    try fields.append("Range", "bytes=0-1".to_bytes())
    try fields.append("If-Range", "Sun, 06 Nov 1994 08:49:38 GMT".to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 200)
    fields.remove("If-Range")
    try fields.append("If-Range", (try http_date(time)).to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 206)
    try fields.append("If-Range", (try http_date(time)).to_bytes())
    try expect_equal(asset_response(Request(headers: fields), value).status, 200)
    fields.remove("If-Range")
    fields.remove("Range")
    try fields.append("Range", "bytes=0-1,8-9".to_bytes())

    let response = asset_response(Request(headers: fields), value)
    let media = response.headers.text("Content-Type").get().get() [0]
    try expect_true(media.split("boundary=") [1].byte_length() <= 70)

from "@std/http.ms" import Server, Router, HttpError, HttpClientOptions, HttpServerOptions, ResponseBody
from "@std/net.ms" import network, TlsOptions
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep
from "./support/certificates.ms" import certificate, private_key

test "asset wire responses preserve HEAD 304 and multipart framing over HTTP1 and HTTP2":
    let options = HttpServerOptions(
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: [], require_client_certificate: False
        )
    )
    let server = Server("127.0.0.1:0", options)
    let owner = server.clone()
    let value = try asset("0123456789".to_bytes(), "text/plain")
    let copied = value.clone()

    with let tasks = TaskGroup[Result[Unit, HttpError]]():
        let task = tasks.spawn(
            lambda channel:
                var routes = Router()
                let representation = copied.clone()
                routes.get("/", lambda request: asset_response(request, representation))
                return owner.run(routes)
        )

        while server.address().is_none(): sleep(1.milliseconds)

        for protocol in ["http/1.1", "h2"]:
            let tls = TlsOptions(
                server_name: "stdlib.test", roots_pem: certificate(),
                certificate_pem: "", private_key_pem: "", alpn: [protocol.clone()],
                require_client_certificate: False
            )

            with let client = try network().http_client(HttpClientOptions(tls: tls)):
                let url = f"https://{server.address().get()}/"

                with let response = try client.request(HttpMethod.Head, url, headers()):
                    try expect_equal(
                        response.metadata().headers.text(
                            "Content-Length"
                        ).get().get() [0],
                        "10"
                    )
                    try expect_equal((try collect(response)).length(), 0)

                let conditional = headers()
                try conditional.append("If-None-Match", value.etag.to_bytes())

                with let response = try client.request(HttpMethod.Get, url, conditional):
                    try expect_equal(response.metadata().status, 304)
                    try expect_equal((try collect(response)).length(), 0)

                let ranges = headers()
                try ranges.append("Range", "bytes=0-1,8-9".to_bytes())

                with let response = try client.request(HttpMethod.Get, url, ranges):
                    try expect_equal(response.metadata().status, 206)

                    let body = (try collect(response)).decode_utf8().get()
                    try expect_true(body.contains("\r\n\r\n01\r\n"))
                    try expect_true(body.contains("\r\n\r\n89\r\n"))

        server.close()

        let result = try task.result()
        let done = try result

def collect(response: ResponseBody) -> Result[Bytes, IoError]:
    var result = "".to_bytes()

    while True:
        let piece = try response.read()
        if piece.is_none(): return ok(result)
        if result.length() + piece.get().length() > 4096: return error(
            IoError.LimitExceeded
        )

        result = result.concat(piece.get())

    return ok(result)
