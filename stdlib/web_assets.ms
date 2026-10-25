from "@std/shared.ms" import share
from "@std/core.ms" import Closeable
from "@std/http.ms" import Request, Response, Body, HttpMethod, HttpError, Router, headers, text_response
from "@std/bytes.ms" import Bytes
from "@std/crypto.ms" import sha256
from "@std/encoding.ms" import hex_encode
from "@std/time.ms" import Timestamp
from "@std/web_dates.ms" import http_date, parse_http_date
from "@std/io.ms" import WriteStream, IoError

# Immutable representation in an explicit asset manifest; construct with asset().
export type Asset:
    # Shared immutable payload; no request path is resolved against the filesystem.
    data: Bytes
    # Validated response media type.
    content_type: String
    # Strong quoted SHA-256 content validator.
    etag: String
    # Optional modification time, compared at whole-second precision.
    modified: Optional[Timestamp]
    # Explicit cache policy shared by successful and conditional responses.
    cache_control: String

# Creates an immutable asset with a strong content hash; rejects control bytes in metadata.
export def asset(
    data: Bytes,
    content_type: String = "application/octet-stream",
    modified: Optional[Timestamp] = none,
    cache_control: String = "public, max-age=0, must-revalidate"
) -> Result[Asset, HttpError]:
    for field in [content_type.clone(), cache_control.clone()]:
        for code in field.scalar_values():
            if code < 32 or code == 127: return error(HttpError.InvalidInput)
    if content_type == "": return error(HttpError.InvalidInput)

    let tag = "\"" + hex_encode(sha256(data)) + "\""
    return ok(Asset(data, content_type, tag, modified, cache_control))

# Explicit URL-path manifest. Clone after construction to freeze the map for a router.
export type Assets:
    # Exact normalized URL paths mapped to immutable representations.
    entries: Map[String, Asset] = Map[String, Asset]()
    # Maximum requested ranges; positive, with an absolute maximum of 64.
    max_ranges: Int = 16

impl Assets:
    # Registers an exact absolute URL path. Parent segments, query/fragment markers and duplicate paths fail.
    var def add(path: String, value: Asset) -> Result[Unit, HttpError]:
        if (
            not path.starts_with("/")
            or path.contains("\\")
            or path.contains("?")
            or path.contains("#")
            or path.split("/").contains("..")
            or self.entries.contains(path)
        ): return error(HttpError.InvalidInput)

        self.entries.add(path, value)
        return ok(())

    # Handles GET/HEAD with validators and bounded byte ranges; missing paths return 404.
    def handle(request: Request) -> Response:
        if self.max_ranges <= 0 or self.max_ranges > 64: return text_response(
            "Invalid asset range policy", 500
        )

        if request.method != HttpMethod.Get and request.method != HttpMethod.Head:
            let response = text_response("Method not allowed", 405)
            response.headers.append("Allow", "GET, HEAD, OPTIONS".to_bytes()).get()
            if request.method == HttpMethod.Options: return Response(
                204, response.headers, Body.Buffered("".to_bytes())
            )

            return response

        let found = self.entries.get(request.path)
        if found.is_none(): return text_response("Not found", 404)

        return asset_response(request, found.get(), self.max_ranges)

    # Snapshots this manifest behind a wildcard route; mount the returned router under any prefix.
    # Paths in the manifest include their final mounted URL prefix.
    def router() -> Router:
        let frozen = self.clone()
        var routes = Router()
        routes.get("/*path", lambda request: frozen.handle(request))
        return routes

def input(request: Request, name: String, combine: Bool = False) -> Optional[String]:
    let values = request.headers.values(name)
    if values.is_none(): return none
    if not combine and values.get().length() != 1: return none

    var remaining = 8192
    var parts = List[String]()

    for bytes in values.get():
        if bytes.length() > remaining: return none

        remaining -= bytes.length()

        let text = bytes.decode_utf8()
        if text.is_none(): return none

        parts.append(text.get().clone())

    return some(parts.join(","))

def one_tag(text: String, expected: String, weak: Bool) -> Bool:
    let value = text.trim()
    if weak and value.starts_with("W/"): return value.drop(2) == expected

    return value == expected

def valid_tag(text: String) -> Bool:
    var value = text.trim().clone()
    if value.starts_with("W/"): value = value.drop(2).clone()
    if (
        value.scalar_length() < 2
        or not value.starts_with("\"")
        or not value.ends_with("\"")
    ): return False

    for code in value.slice(1, value.scalar_length() - 1).get().scalar_values():
        if code < 33 or code == 34 or code == 127 or code > 255: return False
    return True

def matches(text: String, expected: String, weak: Bool) -> Bool:
    if text.trim() == "*": return True

    var quoted = False
    var part = ""
    var matched = False

    for char in text.chars():
        if char == "\"": quoted = not quoted

        if char == "," and not quoted:
            if not valid_tag(part): return False

            matched = matched or one_tag(part, expected, weak)
            part = ""
        else:
            part += char

    if quoted or not valid_tag(part): return False

    return matched or one_tag(part, expected, weak)

def metadata(
    value: Asset,
    status: Int,
    body: Body,
    length: Optional[Int] = none
) -> Response:
    let fields = headers()
    fields.append("Content-Type", value.content_type.to_bytes()).get()
    fields.append("ETag", value.etag.to_bytes()).get()
    fields.append("Cache-Control", value.cache_control.to_bytes()).get()
    fields.append("Accept-Ranges", "bytes".to_bytes()).get()
    fields.append("X-Content-Type-Options", "nosniff".to_bytes()).get()
    if let modified = value.modified: (
        fields
        .append("Last-Modified", http_date(modified).get().to_bytes())
        .get()
    )
    return Response(status, fields, body, length)

# One inclusive validated byte interval.
type Interval:
    first: Int
    last: Int

def decimal(text: String) -> Optional[Int]:
    if text == "": return none

    var value = 0

    for code in text.scalar_values():
        if code < 48 or code > 57: return none

        let digit = code - 48

        if value > (9223372036854775807 - digit) / 10: value = 9223372036854775807
        else: value = value * 10 + digit

    return some(value)

def ranges(text: String, size: Int, max_ranges: Int) -> Optional[List[Interval]]:
    let parts = text.drop(6).split(",")
    if parts.length() > max_ranges: return none

    var result = List[Interval]()

    for item in parts:
        let pair = item.trim().split("-")
        if pair.length() != 2: return none

        if pair[0] == "":
            let suffix = decimal(pair[1])
            if suffix.is_none(): return none
            if suffix.get() == 0 or size == 0: continue

            let first = 0 if suffix.get() >= size else size - suffix.get()

            result.append(Interval(first, size - 1))
            continue

        let first = decimal(pair[0])
        if first.is_none(): return none

        var last = size - 1

        if pair[1] != "":
            let parsed = decimal(pair[1])
            if parsed.is_none() or parsed.get() < first.get(): return none

            if parsed.get() < last: last = parsed.get()

        if first.get() >= size: continue

        result.append(Interval(first.get(), last))

    if result.length() == 0: return none

    return some(result)

def part_head(boundary: String, value: Asset, range: Interval) -> String:
    return f"--{boundary}\r\nContent-Type: {value.content_type}\r\nContent-Range: bytes {range.first}-{range.last}/{value.data.length()}\r\n\r\n"

type Held[T]:
    value: T

impl Closeable for Held[T]:
    var def close() -> Unit: ()

def send_ranges(
    output: WriteStream,
    value: Asset,
    parts: List[Interval],
    boundary: String
) -> Result[Unit, IoError]:
    with Held(share(output)) as destination:
        for range in parts:
            with Held(part_head(boundary, value, range)) as head:
                try destination.value.get().write(head.value)

            var offset = range.first + 0

            while offset <= range.last:
                let remaining = range.last - offset + 1

                let size = 65536 if remaining > 65536 else remaining

                with Held(value.data.slice(offset, offset + size).get()) as chunk:
                    try destination.value.get().write_bytes(chunk.value)
                offset += size

            try destination.value.get().write("\r\n")

        with Held(f"--{boundary}--\r\n") as closing:
            return destination.value.get().write(closing.value)

# Responds from an immutable representation. Preconditions precede ranges; malformed or unsatisfiable ranges return 416.
export def asset_response(
    request: Request,
    value: Asset,
    max_ranges: Int = 16
) -> Response:
    if max_ranges <= 0 or max_ranges > 64: return text_response(
        "Invalid asset range policy", 500
    )

    if request.method != HttpMethod.Get and request.method != HttpMethod.Head:
        let response = text_response("Method not allowed", 405)
        response.headers.append("Allow", "GET, HEAD".to_bytes()).get()
        return response

    let if_match = input(request, "If-Match", True)
    if request.headers.values("If-Match").is_some() and if_match.is_none(): return text_response(
        "Invalid If-Match", 400
    )
    if if_match.is_some() and not matches(if_match.get(), value.etag, False): return metadata(
        value, 412, Body.Buffered("".to_bytes())
    )

    if if_match.is_none():
        if let date = input(request, "If-Unmodified-Since"):
            let parsed = parse_http_date(date)
            if (
                parsed.is_some()
                and value.modified.is_some()
                and value.modified.get().unix_seconds() > parsed.get().unix_seconds()
            ): return metadata(value, 412, Body.Buffered("".to_bytes()))

    let if_none = input(request, "If-None-Match", True)
    if request.headers.values("If-None-Match").is_some() and if_none.is_none(): return text_response(
        "Invalid If-None-Match", 400
    )

    var not_modified = if_none.is_some() and matches(if_none.get(), value.etag, True)

    if if_none.is_none():
        if let date = input(request, "If-Modified-Since"):
            let parsed = parse_http_date(date)
            if (
                parsed.is_some()
                and value.modified.is_some()
                and value.modified.get().unix_seconds() <= parsed.get().unix_seconds()
            ): not_modified = True

    if not_modified: return metadata(
        value, 304, Body.Buffered("".to_bytes()), some(value.data.length())
    )

    let complete = metadata(
        value, 200, Body.Buffered(value.data.clone()), some(value.data.length())
    )
    if request.method != HttpMethod.Get: return complete

    let range = input(request, "Range")
    if range.is_none() or not range.get().starts_with("bytes="): return complete

    let if_range = input(request, "If-Range")
    if request.headers.values("If-Range").is_some() and if_range.is_none(): return complete

    if let condition = if_range:
        var valid = condition == value.etag

        if not condition.starts_with("\"") and not condition.starts_with("W/"):
            let parsed = parse_http_date(condition)
            valid = (
                parsed.is_some()
                and value.modified.is_some()
                and value.modified.get().unix_seconds() == parsed.get().unix_seconds()
            )

        if not valid: return complete

    let selected = ranges(range.get(), value.data.length(), max_ranges)

    if selected.is_none():
        let response = metadata(value, 416, Body.Buffered("".to_bytes()))
        (
            response.headers.append(
                "Content-Range", f"bytes */{value.data.length()}".to_bytes()
            ).get()
        )
        return response

    let parts = selected.get()

    if parts.length() == 1:
        let part = parts[0]
        let response = metadata(
            value,
            206,
            Body.Buffered(
                value.data.slice(part.first, part.last + 1).get()
            ),
            some(part.last - part.first + 1)
        )
        (
            response.headers.append(
                "Content-Range",
                f"bytes {part.first}-{part.last}/{value.data.length()}".to_bytes()
            ).get()
        )
        return response

    let boundary = "ms-" + value.etag.slice(1, value.etag.scalar_length() - 1).get()
    let copied = value.clone()
    let copied_parts = parts.clone()
    let copied_boundary = boundary.clone()
    let body = Body.Stream(
        lambda (output: WriteStream): send_ranges(
            output, copied, copied_parts, copied_boundary
        )
    )
    let response = metadata(value, 206, body)
    response.headers.remove("Content-Type")
    (
        response.headers.append(
            "Content-Type", f"multipart/byteranges; boundary={boundary}".to_bytes()
        ).get()
    )
    return response

from "@std/fs.ms" import filesystem, FileSystemError
from "@std/io.ms" import read_all

# Loads a trusted deployment path into an immutable representation under a byte cap.
# Resolve request URLs only through Assets, never by passing untrusted paths here.
export def load_asset(
    path: String,
    max_bytes: Int,
    content_type: String = "application/octet-stream",
    modified: Optional[Timestamp] = none,
    cache_control: String = "public, max-age=0, must-revalidate"
) -> Result[Asset, HttpError]:
    if max_bytes < 0: return error(HttpError.InvalidInput)

    with try file_result(filesystem().open(path, "r", 0)) as file:
        let data = read_all(file.reader(), some(max_bytes))
        if data.is_error(): return error(HttpError.Failed(data.err().message()))

        return asset(data.get().clone(), content_type, modified, cache_control)

    return error(HttpError.Closed)

def file_result[T](result: Result[T, FileSystemError]) -> Result[T, HttpError]:
    if let value = result.to_optional(): return ok(value)

    return error(HttpError.Failed(result.err().message()))
