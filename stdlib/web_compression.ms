from "@std/core.ms" import Closeable
from "@std/http.ms" import Request, Response, Body, HttpError, Middleware, text_response
from "@std/archive.ms" import CompressionFormat, CompressionWriter, compress_writer
from "@std/io.ms" import WriteStream, IoError
from "@std/bytes.ms" import Bytes

# Explicit gzip response policy. Avoid compressing responses that mix secrets with attacker input.
export type Compression:
    # DEFLATE level from zero through nine.
    level: Int = 6
    # Buffered payloads below this size use identity when identity is acceptable.
    min_bytes: Int = 256
    # Cumulative uncompressed payload budget; none is unlimited.
    max_input_bytes: Optional[Int] = none
    # Cumulative gzip payload budget; none is unlimited. Transport response limits apply independently.
    max_output_bytes: Optional[Int] = none

def quality(text: String) -> Optional[Int]:
    let parts = text.split(".")
    if parts.length() > 2 or (parts[0] != "0" and parts[0] != "1"): return none

    var fraction = 0

    if parts.length() == 2:
        if parts[1].byte_length() > 3: return none

        for digit in parts[1].scalar_values():
            if digit < 48 or digit > 57: return none

            fraction = fraction * 10 + digit - 48

        var padding = parts[1].byte_length()

        while padding < 3:
            fraction *= 10
            padding += 1

    if parts[0] == "1": return some(1000) if fraction == 0 else none

    return some(fraction)

type Accepted:
    gzip: Int
    identity: Int
    explicit: Bool = False
    codings: Map[String, Int] = Map[String, Int]()

def accepted(request: Request) -> Result[Accepted, HttpError]:
    let values = request.headers.values("Accept-Encoding")
    if values.is_none(): return ok(Accepted(0, 1000))

    var size = 0

    for value in values.get():
        if value.length() > 8192 - size: return error(HttpError.LimitExceeded)

        size += value.length()

    var codings = Map[String, Int]()

    for value in values.get():
        let text = value.decode_utf8()
        if text.is_none(): return error(HttpError.InvalidInput)

        for item in text.get().split(","):
            if item.trim() == "": continue

            let parts = item.trim().lower().split(";")
            if parts.length() > 2: return error(HttpError.InvalidInput)

            let name = parts[0].trim().clone()
            if codings.contains(name): return error(HttpError.InvalidInput)

            var weight = 1000

            if parts.length() == 2:
                let parameter = parts[1].trim().split("=")
                if parameter.length() != 2 or parameter[0].trim() != "q": return error(
                    HttpError.InvalidInput
                )

                let parsed = quality(parameter[1].trim())
                if parsed.is_none(): return error(HttpError.InvalidInput)

                weight = parsed.get()

            codings.add(name, weight)

    let wildcard = codings.get("*").get(0)
    let gzip = codings.get("gzip").get(wildcard)
    let identity = (
        codings
        .get("identity")
        .get(0 if codings.get("*") == some(0) else 1000)
    )
    return ok(Accepted(gzip, identity, True, codings))

def has_directive(response: Response, directive: String) -> Bool:
    if let fields = response.headers.text("Cache-Control").get():
        for field in fields:
            for item in field.split(","):
                if item.trim().lower() == directive: return True
    return False

def varies(response: Response) -> Unit:
    if let fields = response.headers.text("Vary").get():
        for field in fields:
            for item in field.split(","):
                if item.trim() == "*" or item.trim().lower() == "accept-encoding": return
    response.headers.append("Vary", "Accept-Encoding".to_bytes()).get()

type Held[T]:
    value: T

impl Closeable for Held[T]:
    var def close() -> Unit: ()

def encoding_writer(
    policy: Compression,
    output: WriteStream
) -> Result[CompressionWriter, IoError]:
    let created = compress_writer(
        output, level: policy.level, max_input_bytes: policy.max_input_bytes,
        max_output_bytes: policy.max_output_bytes
    )
    if created.is_error(): return error(IoError.Failed(created.err().message()))

    return ok(created.get().clone())

def encode_stream(
    policy: Compression,
    produce: Callable[[WriteStream], Result[Unit, IoError]],
    output: WriteStream
) -> Result[Unit, IoError]:
    with let writer = try encoding_writer(policy, output):
        with let destination = Held(writer.writer()):
            try produce(destination.value)
            return writer.finish()

# Returns ordinary middleware. Negotiates gzip and identity, including explicit q=0 and 406.
# Existing encodings, ranges, upgrades, bodyless statuses and no-transform are not compressed.
# Streams retain bounded staging/backpressure and producer errors abort without a successful trailer.
export def compression(
    policy: Compression = Compression()
) -> Result[Middleware, HttpError]:
    if policy.level < 0 or policy.level > 9 or policy.min_bytes < 0: return error(
        HttpError.InvalidInput
    )
    if policy.max_input_bytes.get(0) < 0 or policy.max_output_bytes.get(0) < 0: return error(
        HttpError.InvalidInput
    )

    let frozen = policy.clone()
    return ok(Middleware(lambda request, next: dispatch(frozen, request, next)))

def compression_error(message: String) -> Response:
    let response = text_response(message, 500)
    varies(response)
    return response

def unacceptable() -> Response:
    let response = text_response("No acceptable content encoding", 406)
    varies(response)
    return response

def dispatch(
    policy: Compression,
    request: Request,
    next: Callable[[Request], Response]
) -> Response:
    with let negotiated = Held(accepted(request)):
        if negotiated.value.is_error(): return text_response(
            "Invalid Accept-Encoding", 400
        )

        with let response = Held(next(request)):
            return encode_response(
                policy, request, negotiated.value.get(), response.value
            )

def encode_response(
    policy: Compression,
    request: Request,
    preference: Accepted,
    original_response: Response
) -> Response:
    var response = original_response.clone()
    varies(response)

    let existing = response.headers.text("Content-Encoding").get()

    if let fields = existing:
        if not preference.explicit: return response

        for field in fields:
            for item in field.split(","):
                let name = item.trim().lower()

                let weight = preference.identity if name == "identity" else preference.codings.get(
                    name
                ).get(preference.codings.get("*").get(0))

                if weight == 0: return unacceptable()

        return response

    var skip = (
        response.status < 200
        or response.status == 204
        or response.status == 205
        or response.status == 304
        or response.status == 206
    )
    skip = (
        skip
        or response.headers.values("Content-Range").is_some()
        or request.headers.values("Range").is_some()
        or has_directive(response, "no-transform")
    )
    if let fields = request.headers.text("Cache-Control").get():
        for field in fields:
            for item in field.split(","):
                if item.trim().lower() == "no-transform": skip = True

    if skip:
        if (
            preference.identity == 0
            and response.status >= 200
            and response.status != 204
            and response.status != 205
            and response.status != 304
        ): return unacceptable()

        return response

    var size: Optional[Int] = none

    match response.body:
        case Buffered(data): size = some(data.length())
        case Stream(produce): size = none
        case Upgrade(handler, origins, protocols, limit): skip = True

    if skip: return response

    let use_gzip = (
        preference.gzip > 0
        and (
            preference.identity == 0
            or (
                preference.gzip >= preference.identity
                and size.get(policy.min_bytes) >= policy.min_bytes
            )
        )
    )

    if not use_gzip:
        if preference.identity == 0: return unacceptable()

        return response

    let original = response.body.clone()

    match original:
        case Buffered(data):
            if let limit = policy.max_input_bytes:
                if data.length() > limit: return compression_error(
                    "Response limit exceeded"
                )

            let encoded = (
                CompressionFormat
                .Gzip
                .compress(data, policy.level, policy.max_output_bytes)
            )
            if encoded.is_error(): return compression_error(
                "Response compression failed"
            )

            response.body = Body.Buffered(encoded.get().clone())
        case Stream(produce):
            response.body = Body.Stream(
                lambda output: encode_stream(policy, produce, output)
            )
        case Upgrade(handler, origins, protocols, limit): return response

    response.content_length = none
    for name in [
        "Content-Length", "Content-MD5", "Digest", "Content-Digest", "Repr-Digest"
    ]: (response.headers.remove(name))

    if let tags = response.headers.text("ETag").get():
        if tags.length() == 1 and tags[0].trim().starts_with("\""):
            let weak = "W/" + tags[0].trim()
            response.headers.remove("ETag")
            response.headers.append("ETag", weak.to_bytes()).get()

    response.headers.append("Content-Encoding", "gzip".to_bytes()).get()
    return response
