from "@std/web_compression.ms" import Compression, compression
from "@std/http.ms" import Router, Request, Response, Body, HttpMethod, headers, text_response, stream_response
from "@std/archive.ms" import CompressionFormat
from "@std/io.ms" import WriteStream, IoError
from "@std/shared.ms" import Shared, share
from "@std/bytes.ms" import Bytes
from "@std/testing.ms" import expect_equal, expect_true

def payload(response: Response) -> Bytes:
    match response.body:
        case Buffered(bytes): return bytes.clone()
        case _: return "".to_bytes()

type Sink:
    bytes: Shared[Bytes]

impl WriteStream for Sink:
    var def close() -> Unit: return ()

    var def flush() -> Result[Unit, IoError]: return ok(())

    var def write(data: String) -> Result[Unit, IoError]: return self.write_bytes(
        data.to_bytes()
    )

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        let old = self.bytes.take()
        self.bytes.put(old.concat(data))
        return ok(())

test "gzip negotiation handles qualities identity refusal and cache metadata":
    var routes = Router()
    routes.use((try compression(Compression(min_bytes: 0))).call)

    routes.get(
        "/",
        lambda request:
            let response = text_response("hello hello hello")
            response.headers.append("ETag", "\"strong\"".to_bytes()).get()
            return response
    )

    let fields = headers()
    try fields.append("Accept-Encoding", "gzip".to_bytes())

    let compressed = routes.handle(Request(headers: fields))
    try expect_equal(
        compressed.headers.text("Content-Encoding").get().get() [0], "gzip"
    )
    try expect_equal(compressed.headers.text("ETag").get().get() [0], "W/\"strong\"")
    try expect_equal(
        (
            try CompressionFormat
            .Gzip
            .decompress(payload(compressed))
        ).decode_utf8().get(),
        "hello hello hello"
    )
    fields.remove("Accept-Encoding")
    try fields.append("Accept-Encoding", "gzip;q=0.5, identity;q=1".to_bytes())

    let identity = routes.handle(Request(headers: fields))
    try expect_true(identity.headers.values("Content-Encoding").is_none())
    try expect_true(identity.headers.values("Vary").is_some())
    fields.remove("Accept-Encoding")
    try fields.append("Accept-Encoding", "gzip;q=0, identity;q=0".to_bytes())
    try expect_equal(routes.handle(Request(headers: fields)).status, 406)
    fields.remove("Accept-Encoding")
    try fields.append("Accept-Encoding", "gzip;q=1.001".to_bytes())
    try expect_equal(routes.handle(Request(headers: fields)).status, 400)

test "stream compression flushes and finalizes only after successful production":
    var routes = Router()
    routes.use((try compression()).call)
    routes.get(
        "/",
        lambda request: stream_response(
            lambda (var output: WriteStream):
                try output.write("first")
                try output.flush()
                return output.write("second")
        )
    )

    let fields = headers()
    try fields.append("Accept-Encoding", "gzip".to_bytes())

    let response = routes.handle(Request(headers: fields))
    let bytes = share("".to_bytes())

    match response.body:
        case Stream(produce): try produce(Sink(bytes))
        case _: try expect_true(False)

    try expect_equal(
        (
            try CompressionFormat
            .Gzip
            .decompress(bytes.get().clone())
        ).decode_utf8().get(),
        "firstsecond"
    )

test "no-transform and range responses keep their representation":
    var routes = Router()
    routes.use((try compression(Compression(min_bytes: 0))).call)

    routes.get(
        "/",
        lambda request:
            let response = text_response("unchanged")
            (
                response.headers.append(
                    "Cache-Control", "private, no-transform".to_bytes()
                ).get()
            )
            return response
    )

    let fields = headers()
    try fields.append("Accept-Encoding", "gzip".to_bytes())

    let response = routes.handle(Request(headers: fields))
    try expect_true(response.headers.values("Content-Encoding").is_none())
    try expect_equal(payload(response).decode_utf8().get(), "unchanged")
