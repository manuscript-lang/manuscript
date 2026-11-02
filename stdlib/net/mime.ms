import Bytes, BytesBuilder from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"

# MIME building blocks: media types, header blocks, and multipart bodies.
# `parse_media_type` splits `text/html; charset=utf-8`; `parse_headers` reads an RFC 5322 style
# header block (folded lines joined, names kept as written, lookup case-insensitive);
# `parse_multipart` and `encode_multipart` read and write `multipart/form-data` and `multipart/mixed` bodies.
#
#     import parse_media_type, media_type_for_extension from "@std/net/mime.ms"
#     media_type_for_extension(".json")                     # "application/json"
#     parse_media_type("text/html; charset=utf-8").get().params["charset"]

# Errors returned for malformed media types, header blocks, or multipart bodies.
export type MimeError:
    # A media type is not `type/subtype` or a parameter is malformed.
    case InvalidMediaType
    # A header line has no colon or begins with a fold.
    case InvalidHeader
    # The boundary is empty or absent, or the body lacks the opening or closing delimiter.
    case InvalidMultipart

# A parsed media type with lower-cased `essence` and parameters keyed by lower-cased name.
export type MediaType:
    # Lower-cased `type/subtype`, such as `text/html`.
    essence: String
    # Parameters such as `charset` or `boundary`; quoted values are unquoted.
    params: Map[String, String] = Map[String, String]()

# One header field. `name` keeps the sender's spelling; `value` has folding removed.
export type HeaderField:
    # Field name as written, without the colon.
    name: String
    # Field value with leading and trailing space trimmed and folded lines joined by one space.
    value: String

# A parsed header block that can be looked up by name regardless of case.
export type Headers:
    # Fields in the order they appeared; repeated names stay separate entries.
    fields: List[HeaderField] = List[HeaderField]()

# One multipart part: its headers, the decoded `name` and `filename` from Content-Disposition, and body bytes.
export type Part:
    # Part header fields; `Content-Disposition` and `Content-Type` live here.
    headers: Headers = Headers()
    # Form field name from `Content-Disposition`, or empty text.
    name: String = ""
    # Uploaded file name from `Content-Disposition`, or empty text.
    filename: String = ""
    # Part body without the delimiter line breaks.
    data: Bytes

impl Headers:
    # Returns the first value for `name`, ignoring case, or none.
    fn get(name: String) String?:
        let wanted = name.lower()
        for field in self.fields:
            if field.name.lower() == wanted: return field.value.clone()
        return none

    # Returns every value for `name`, ignoring case, in order.
    fn get_all(name: String) List[String]:
        let wanted = name.lower()
        var values = List[String]()
        for field in self.fields:
            if field.name.lower() == wanted: values.append(field.value.clone())
        return values

    # Writes the block as `Name: value` lines with CRLF endings.
    fn to_text() String:
        var out = StringBuilder()
        for field in self.fields:
            out.append("{field.name}: {field.value}\r\n")
        return out.build()

# Extension table behind `media_type_for_extension`.
let TYPES = {
    "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
    "css": "text/css; charset=utf-8", "js": "text/javascript; charset=utf-8",
    "mjs": "text/javascript; charset=utf-8", "txt": "text/plain; charset=utf-8",
    "csv": "text/csv; charset=utf-8", "md": "text/markdown; charset=utf-8",
    "xml": "text/xml; charset=utf-8", "json": "application/json",
    "pdf": "application/pdf", "zip": "application/zip", "gz": "application/gzip",
    "tar": "application/x-tar", "wasm": "application/wasm", "toml": "application/toml",
    "yaml": "application/yaml", "yml": "application/yaml", "png": "image/png",
    "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
    "svg": "image/svg+xml", "ico": "image/x-icon", "mp3": "audio/mpeg",
    "wav": "audio/wav", "mp4": "video/mp4", "webm": "video/webm", "woff": "font/woff",
    "woff2": "font/woff2", "ttf": "font/ttf"
}

# Returns the media type for a file extension with or without the leading dot (case-insensitive), or none when unknown.
export fn media_type_for_extension(extension: String) String?:
    let key = extension.lower().cut_prefix(".").get(extension.lower())
    return TYPES.get(key)

# Returns the first extension, with its dot, registered for a media type (parameters ignored), or none.
export fn extension_for_media_type(media_type: String) String?:
    let wanted = media_type.split(";")[0].trim().lower()
    for entry in TYPES.entries():
        if entry.value.split(";")[0] == wanted: return ".{entry.key}"
    return none

# Parses `type/subtype; name=value; name="quoted value"`. Names and the essence are lower-cased;
# a missing slash, empty part, or unterminated quote is `InvalidMediaType`.
export fn parse_media_type(text: String) MediaType!MimeError:
    let pieces = split_params(text)
    let essence = pieces[0].trim().lower()
    let parts = essence.split("/")
    if (
        parts.length() != 2
        or parts[0].is_empty()
        or parts[1].is_empty()
        or essence.contains(" ")
    ):
        return error(MimeError.InvalidMediaType)

    var params = Map[String, String]()

    for i in 1..pieces.length():
        let piece = pieces[i].trim()
        if piece.is_empty(): continue

        let at = piece.index_of("=")
        if not at.is_some(): return error(MimeError.InvalidMediaType)

        let name = piece.take(at.get(0)).trim().lower()
        let raw = piece.drop(at.get(0) + 1).trim()
        if name.is_empty(): return error(MimeError.InvalidMediaType)

        let value = unquote(raw)
        if not value.is_some(): return error(MimeError.InvalidMediaType)

        params.add(name, value.get(""))

    return ok(MediaType(essence: essence, params: params))

# Formats a media type as `essence; name=value`, quoting values that are not simple tokens.
export fn format_media_type(media_type: MediaType) String:
    var out = media_type.essence.clone()
    for entry in media_type.params.entries():
        out = "{out}; {entry.key}={quote_value(entry.value)}"
    return out

# Splits on `;` outside double quotes.
fn split_params(text: String) List[String]:
    var pieces = List[String]()
    var current = StringBuilder()
    var quoted = false
    var escaped = false

    for c in text.chars():
        if escaped:
            current.append(c)
            escaped = false
        else if quoted and c == "\\":
            current.append(c)
            escaped = true
        else if c == "\"":
            current.append(c)
            quoted = not quoted
        else if c == ";" and not quoted:
            pieces.append(current.drain())
        else:
            current.append(c)

    pieces.append(current.drain())
    return pieces

# Returns the unquoted value, or none for an unterminated quote.
fn unquote(raw: String) String?:
    if not raw.starts_with("\""): return raw.clone()
    if raw.length() < 2 or not raw.ends_with("\""): return none

    var out = StringBuilder()
    var escaped = false

    for c in raw.slice(1, raw.length() - 1).get("").chars():
        if escaped:
            out.append(c)
            escaped = false
        else if c == "\\":
            escaped = true
        else:
            out.append(c)

    return out.build()

fn is_token(value: String) Bool:
    if value.is_empty(): return false

    return not value.contains_any(" \t\"(),/:;<=>?@[\\]\{\}")

fn quote_value(value: String) String:
    if is_token(value): return value.clone()

    let escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
    return "\"{escaped}\""

# Parses a header block (up to the first blank line). Continuation lines starting with space or tab
# join the previous value with one space. A line without a colon, or a fold before any field, is `InvalidHeader`.
export fn parse_headers(text: String) Headers!MimeError:
    var fields = List[HeaderField]()

    for raw in text.lines():
        let line = raw.trim_end_chars("\r")
        if line.is_empty(): break

        if line.starts_with(" ") or line.starts_with("\t"):
            if fields.is_empty(): return error(MimeError.InvalidHeader)

            let last = fields.length() - 1
            fields[last] = HeaderField(
                name: fields[last].name.clone(),
                value: "{fields[last].value} {line.trim()}"
            )
            continue

        let at = line.index_of(":")
        if not at.is_some() or at.get(0) == 0: return error(MimeError.InvalidHeader)

        fields.append(
            HeaderField(
                name: line.take(at.get(0)).trim(),
                value: line.drop(at.get(0) + 1).trim()
            )
        )

    return ok(Headers(fields: fields))

# Returns the boundary parameter of a `multipart/*` Content-Type value, or none.
export fn multipart_boundary(content_type: String) String?:
    let parsed = parse_media_type(content_type)
    if not parsed.is_ok(): return none

    let media = parsed.get()
    if not media.essence.starts_with("multipart/"): return none

    return media.params.get("boundary")

# Splits a multipart body into parts using `boundary`. Text before the first delimiter and after the
# closing delimiter is ignored. Parts keep their body bytes exactly; headers are parsed as `Headers`.
# A body without a closing delimiter is `InvalidMultipart`.
export fn parse_multipart(body: Bytes, boundary: String) List[Part]!MimeError:
    if boundary.is_empty(): return error(MimeError.InvalidMultipart)

    let crlf = "\r\n".to_bytes()
    let sections = crlf.concat(body).split("\r\n--{boundary}".to_bytes(), none)
    var parts = List[Part]()

    for i in 1..sections.length():
        let section = sections[i]
        if section.starts_with("--".to_bytes()): return ok(parts)
        if not section.starts_with(crlf): return error(MimeError.InvalidMultipart)

        let inner = section.slice(2, section.length()).get("".to_bytes())
        let blank = if inner.starts_with(crlf): 0 else: inner.index_of(
            "\r\n\r\n".to_bytes()
        ).get(-1)
        if blank < 0 and not inner.starts_with(crlf): return error(
            MimeError.InvalidMultipart
        )

        let skip = if blank == 0: 2 else: 4
        let headers = try parse_headers(inner.decode_utf8_range(0, blank).get(""))
        var part = Part(
            headers: headers,
            data: inner.slice(blank + skip, inner.length()).get(
                "".to_bytes()
            )
        )

        if let disposition = part.headers.get("Content-Disposition"):
            let media = parse_media_type(
                "x/x{disposition.drop(disposition.index_of(";").get(disposition.length()))}"
            )

            if media.is_ok():
                part.name = media.get().params.get("name").get("")
                part.filename = media.get().params.get("filename").get("")

        parts.append(part)

    return error(MimeError.InvalidMultipart)

# Encodes parts as a multipart body closed with the final delimiter. Each part's headers are
# written as given, then a blank line and the data.
export fn encode_multipart(parts: List[Part], boundary: String) Bytes:
    var out = BytesBuilder()

    for part in parts:
        out.append_bytes("--{boundary}\r\n{part.headers.to_text()}\r\n".to_bytes())
        out.append_bytes(part.data)
        out.append_bytes("\r\n".to_bytes())

    out.append_bytes("--{boundary}--\r\n".to_bytes())
    return out.build()

# Builds a form-data part for a field; pass `filename` to mark an upload.
export fn form_part(
    name: String,
    data: Bytes,
    filename: String = "",
    content_type: String = ""
) Part:
    var disposition = "form-data; name={quote_value(name)}"
    if not filename.is_empty(): disposition = "{disposition}; filename={quote_value(filename)}"

    var fields = [HeaderField(name: "Content-Disposition", value: disposition)]
    if not content_type.is_empty(): fields.append(
        HeaderField(name: "Content-Type", value: content_type)
    )
    return Part(
        headers: Headers(fields: fields), name: name, filename: filename, data: data
    )

impl Error for MimeError:
    # Returns a MIME-prefixed diagnostic without echoing the input.
    fn message() String:
        match self:
            InvalidMediaType: return "MIME: invalid media type"
            InvalidHeader: return "MIME: invalid header"
            InvalidMultipart: return "MIME: invalid multipart body"
