import StringBuilder from "@std/string.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import parse_int_radix from "@std/text.ms"
import base64_decode, latin1_decode from "@std/data/encoding.ms"
import Headers, HeaderField, parse_headers from "@std/net/mime.ms"

# Internet mail messages (RFC 5322): addresses, address lists, and message parsing.
# `parse_address("Ada <ada@example.com>")` gives name and address; `parse_message` splits a raw
# message into `Headers` and body and decodes RFC 2047 encoded words on request.
#
#     import parse_address, parse_message from "@std/net/mail.ms"
#     let from = parse_address("Ada Lovelace <ada@example.com>").get()
#     from.name                      # "Ada Lovelace"
#     let mail = parse_message(raw).get()
#     mail.headers.get("Subject")

# Errors returned for malformed addresses or messages.
export type MailError:
    # An address lacks a local part, an `@`, or a domain, or has unbalanced quotes or brackets.
    case InvalidAddress
    # The header block is malformed or the message is empty.
    case InvalidMessage

# A mailbox: optional display name and the `local@domain` address.
export type Address:
    # Display name with quotes removed; empty when none was given.
    name: String = ""
    # The `local@domain` address without angle brackets.
    address: String

# A parsed message: header fields and the body after the first blank line.
export type Message:
    # Header block with folded lines joined.
    headers: Headers
    # Body text exactly as written after the blank line, with line endings kept.
    body: String

impl Address:
    # Formats as `Name <addr>` (quoting the name when it has specials) or the bare address when unnamed.
    fn to_text() String:
        if self.name.is_empty(): return self.address.clone()

        let specials = self.name.contains_any("()<>[]:;@\\,.\"")

        if specials:
            let escaped = self.name.replace("\\", "\\\\").replace("\"", "\\\"")
            return "\"{escaped}\" <{self.address}>"

        return "{self.name} <{self.address}>"

# Parses one mailbox: `addr`, `<addr>`, `Name <addr>` or `"Quoted, Name" <addr>`. Encoded words in
# the name are decoded. Comments are not supported.
export fn parse_address(text: String) Address!MailError:
    let trimmed = text.trim()
    if trimmed.is_empty(): return error(MailError.InvalidAddress)

    var name = ""
    var address = trimmed.clone()

    if let open = trimmed.last_index_of("<"):
        if not trimmed.ends_with(">"): return error(MailError.InvalidAddress)

        name = trimmed.take(open).trim()
        address = trimmed.slice(open + 1, trimmed.length() - 1).get("").trim()
    else if trimmed.contains(">"):
        return error(MailError.InvalidAddress)

    if name.starts_with("\""):
        if name.length() < 2 or not name.ends_with("\""): return error(
            MailError.InvalidAddress
        )

        name = name.slice(1, name.length() - 1).get("").replace("\\\"", "\"").replace(
            "\\\\", "\\"
        )

    if not valid_address(address): return error(MailError.InvalidAddress)

    return ok(Address(name: decode_words(name), address: address))

fn valid_address(address: String) Bool:
    let at = address.last_index_of("@")
    if not at.is_some(): return false

    let local = address.take(at.get(0))
    let domain = address.drop(at.get(0) + 1)
    if local.is_empty() or domain.is_empty(): return false

    return not address.contains_any(" \t<>,;")

# Parses a comma-separated address list, honoring quoted names and angle brackets.
# Empty items (a trailing comma) are skipped; an empty list is an empty result.
export fn parse_address_list(text: String) List[Address]!MailError:
    var out = List[Address]()
    var current = StringBuilder()
    var quoted = false
    var depth = 0
    var pieces = List[String]()

    for c in text.chars():
        if c == "\"": quoted = not quoted
        if not quoted and c == "<": depth += 1
        if not quoted and c == ">": depth -= 1

        if c == "," and not quoted and depth == 0:
            pieces.append(current.drain())
        else:
            current.append(c)

    pieces.append(current.drain())

    for piece in pieces:
        if piece.trim().is_empty(): continue

        out.append(try parse_address(piece))

    return ok(out)

# Splits a raw message at the first blank line into headers and body.
# Both CRLF and LF line endings are accepted; a message without a blank line has an empty body.
export fn parse_message(raw: String) Message!MailError:
    if raw.trim().is_empty(): return error(MailError.InvalidMessage)

    var head = ""
    var body = ""
    let crlf = raw.index_of("\r\n\r\n")
    let lf = raw.index_of("\n\n")

    if let at = crlf:
        head = raw.take(at)
        body = raw.drop(at + 4)
    else if let at = lf:
        head = raw.take(at)
        body = raw.drop(at + 2)
    else:
        head = raw.clone()

    let headers = parse_headers(head)
    if headers.is_error(): return error(MailError.InvalidMessage)

    return ok(Message(headers: headers.get(), body: body))

# Decodes RFC 2047 encoded words (`=?utf-8?B?...?=` and `=?utf-8?Q?...?=`) in header text.
# Only UTF-8, US-ASCII and ISO-8859-1 charsets are decoded; any other word is left as written.
export fn decode_words(text: String) String:
    if not text.contains("=?"): return text.clone()

    var out = StringBuilder()
    var rest = text.clone()
    var previous_encoded = false

    while true:
        let start = rest.index_of("=?")

        if not start.is_some():
            out.append(rest)
            break

        let head = rest.take(start.get(0))
        let tail = rest.drop(start.get(0))
        let parts = tail.split("?")

        # parts: ["=", charset, encoding, payload, "=<remaining>", ...rest of the text split on "?"]
        if parts.length() < 5 or not parts[4].starts_with("="):
            out.append(head)
            out.append(tail.take(2))
            rest = tail.drop(2)
            previous_encoded = false
            continue

        let decoded = decode_word(parts[1], parts[2], parts[3])

        if not decoded.is_some():
            out.append(head)
            out.append(tail.take(2))
            rest = tail.drop(2)
            previous_encoded = false
            continue

        # Whitespace between two adjacent encoded words is dropped.
        if not (previous_encoded and head.trim().is_empty()): out.append(head)
        out.append(decoded.get(""))
        rest = parts.slice(4, parts.length()).get(List[String]()).join("?").drop(1)
        previous_encoded = true

    return out.build()

fn decode_word(charset: String, encoding: String, payload: String) String?:
    let set = charset.lower()
    let kind = encoding.upper()
    var bytes = "".to_bytes()

    if kind == "B":
        let decoded = base64_decode(payload)
        if decoded.is_error(): return none

        bytes = decoded.get()
    else if kind == "Q":
        bytes = q_decode(payload)
    else:
        return none

    if set == "utf-8" or set == "us-ascii": return bytes.decode_utf8()
    if set == "iso-8859-1" or set == "latin1":
        return latin1_decode(bytes)

    return none

fn q_decode(payload: String) Bytes:
    var out = BytesBuilder()
    let chars = payload.chars()
    var i = 0

    while i < chars.length():
        let c = chars[i]

        if c == "_":
            out.append(32)
        else if c == "=" and i + 2 < chars.length():
            let value = parse_int_radix("{chars[i + 1]}{chars[i + 2]}", 16)

            if value.is_some():
                out.append(value.get(0).to_uint8().get(0))
                i += 2
            else:
                out.append(61)
        else:
            for b in c.to_bytes().values():
                out.append(b)

        i += 1

    return out.build()

impl Error for MailError:
    # Returns a mail-prefixed diagnostic without echoing the input.
    fn message() String:
        match self:
            InvalidAddress: return "mail: invalid address"
            InvalidMessage: return "mail: invalid message"
