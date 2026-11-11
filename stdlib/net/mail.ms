import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	base64_decode, latin1_decode from "@std/data/encoding.ms",
	parse_int from "@std/math/math.ms",
	Headers, parse_headers from "@std/net/mime.ms",
	StringBuilder from "@std/string.ms",
)

/*
Internet mail messages (RFC 5322): addresses, address lists, and message parsing.
`parse_address("Ada <ada@example.com>")` gives name and address; `parse_message` splits a raw
message into `Headers` and body and decodes RFC 2047 encoded words on request.

    import parse_address, parse_message from "@std/net/mail.ms"
    sender := parse_address("Ada Lovelace <ada@example.com>")?
    print(sender.name)              // "Ada Lovelace"
    mail := parse_message(raw)?
    print(mail.headers.get("Subject").get(""))
*/

// A mailbox: optional display name and the `local@domain` address.
export type Address:
	// Display name with quotes removed; empty when none was given.
	name: String = ""
	// The `local@domain` address without angle brackets.
	address: String

// Formats as `Name <addr>` (quoting the name when it has specials) or the bare address when unnamed.
fn Address.to_text() String:
	if self.name.is_empty(): return self.address.clone()

	specials := self.name.contains_any("()<>[]:;@\\,.\"")

	if specials:
		escaped := self.name.replace("\\", "\\\\").replace("\"", "\\\"")
		return "\"{escaped}\" <{self.address}>"

	return "{self.name} <{self.address}>"

// A parsed message: header fields and the body after the first blank line.
export type Message:
	// Header block with folded lines joined.
	headers: Headers
	// Body text exactly as written after the blank line, with line endings kept.
	body: String

// Parses one mailbox: `addr`, `<addr>`, `Name <addr>` or `"Quoted, Name" <addr>`. Encoded words in
// the name are decoded. Comments are not supported.
export fn parse_address(text: String) Address!:
	trimmed := text.trim()
	if trimmed.is_empty(): return error(Error("mail: invalid address", kind: "EBADMSG"))

	var name = ""
	var address = trimmed.clone()

	if open := trimmed.last_index_of("<"):
		if not trimmed.ends_with(">"): return error(
			Error("mail: invalid address", kind: "EBADMSG")
		)

		name = trimmed.take(open).trim()
		address = trimmed.slice(open + 1, trimmed.length() - 1).get("").trim()
	else if trimmed.contains(">"):
		return error(Error("mail: invalid address", kind: "EBADMSG"))

	if name.starts_with("\""):
		if name.length() < 2 or not name.ends_with("\""): return error(
			Error("mail: invalid address", kind: "EBADMSG")
		)

		name = name.slice(1, name.length() - 1).get("").replace("\\\"", "\"").replace(
			"\\\\", "\\"
		)

	if not valid_address(address): return error(
		Error("mail: invalid address", kind: "EBADMSG")
	)

	return ok(Address(name: decode_words(name), address: address))

fn valid_address(address: String) Bool:
	at := address.last_index_of("@")
	if at.is_none(): return false

	local := address.take(at.get(0))
	domain := address.drop(at.get(0) + 1)
	if local.is_empty() or domain.is_empty(): return false

	return not address.contains_any(" \t<>,;")

// Parses a comma-separated address list, honoring quoted names and angle brackets.
// Empty items (a trailing comma) are skipped; an empty list is an empty result.
export fn parse_address_list(text: String) List[Address]!:
	var out = List[Address]()
	var current = StringBuilder()
	var quoted = false
	var escaped = false
	var depth = 0
	var pieces = List[String]()

	for c in text.chars():
		if escaped:
			escaped = false
			current.append(c)
			continue

		if quoted and c == "\\":
			escaped = true
			current.append(c)
			continue

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

		out.append(parse_address(piece)?)

	return ok(out)

// Splits a raw message at the first blank line into headers and body.
// Both CRLF and LF line endings are accepted; a message without a blank line has an empty body.
export fn parse_message(raw: String) Message!:
	if raw.trim().is_empty(): return error(
		Error("mail: invalid message", kind: "EBADMSG")
	)

	var head = ""
	var body = ""
	crlf := raw.index_of("\r\n\r\n")
	lf := raw.index_of("\n\n")

	// The first blank line ends the headers, whichever line ending it uses.
	var at = -1
	var skip = 0

	if found := crlf:
		at = found
		skip = 4

	if found := lf:
		if at < 0 or found < at:
			at = found
			skip = 2

	if at >= 0:
		head = raw.take(at)
		body = raw.drop(at + skip)
	else:
		head = raw.clone()

	headers := parse_headers(head)
	if headers.is_error(): return error(Error("mail: invalid message", kind: "EBADMSG"))

	return ok(Message(headers: headers.get(), body: body))

// Decodes RFC 2047 encoded words (`=?utf-8?B?...?=` and `=?utf-8?Q?...?=`) in header text.
// Only UTF-8, US-ASCII and ISO-8859-1 charsets are decoded; any other word is left as written.
export fn decode_words(text: String) String:
	if not text.contains("=?"): return text.clone()

	// Splitting at `?` once keeps decoding linear. A word starts where a field ends in `=` and takes the
	// next three fields (charset, encoding, payload); the field after them must start with the closing `=`.
	fields := text.split("?")
	var out = StringBuilder()
	var head = StringBuilder()
	var previous_encoded = false
	var index = 0
	var seg = fields[0].clone()

	while true:
		if index == fields.length() - 1 or not seg.ends_with("="):
			head.append(seg)
			if index == fields.length() - 1: break

			head.append("?")
			index += 1
			seg = fields[index].clone()
			continue

		head.append(seg.take(seg.scalar_length() - 1))

		literal := head.drain()
		var decoded: String? = none
		if index + 4 < fields.length() and fields[index + 4].starts_with("="):
			decoded = decode_word(
				fields[index + 1], fields[index + 2], fields[index + 3]
			)

		if decoded.is_none():
			out.append(literal)
			out.append("=?")
			previous_encoded = false
			index += 1
			seg = fields[index].clone()
			continue

		// Whitespace between two adjacent encoded words is dropped.
		if not (previous_encoded and literal.trim().is_empty()): out.append(literal)
		out.append(decoded.get(""))
		previous_encoded = true
		seg = fields[index + 4].drop(1)
		index += 4

	out.append(head.drain())
	return out.build()

fn decode_word(charset: String, encoding: String, payload: String) String?:
	set := charset.lower()
	kind := encoding.upper()
	var bytes = "".to_bytes()

	if kind == "B":
		decoded := base64_decode(payload)
		if decoded.is_error(): return none

		bytes = decoded.get()
	else if kind == "Q":
		bytes = q_decode(payload)
	else:
		return none

	if set == "utf-8" or set == "us-ascii": return bytes.decode_utf8()
	if set == "iso-8859-1" or set == "latin1": return latin1_decode(bytes)

	return none

fn q_decode(payload: String) Bytes:
	var out = BytesBuilder()
	chars := payload.chars()
	var i = 0

	while i < chars.length():
		c := chars[i]

		if c == "_":
			out.append(32)
		else if c == "=" and i + 2 < chars.length():
			value := parse_int("{chars[i + 1]}{chars[i + 2]}", 16)

			if value.is_ok():
				out.append(value.get(0).to_uint8().get(0))
				i += 2
			else:
				out.append(61)
		else:
			for b in c.to_bytes().values():
				out.append(b)

		i += 1

	return out.build()
