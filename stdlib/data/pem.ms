import (
	Bytes from "@std/bytes.ms",
	base64_decode, base64_encode from "@std/data/encoding.ms",
	StringBuilder from "@std/string.ms",
)

/*
PEM (RFC 7468) text armor: `-----BEGIN LABEL-----`, base64 body, `-----END LABEL-----`.
Certificates, keys and CSRs travel as PEM blocks; `parse` finds every block in a text and
`encode_all` writes blocks back with 64-column lines.

    import parse, encode_all, PemBlock from "@std/data/pem.ms"
    blocks := try parse(text)
    print(blocks[0].label)         // "CERTIFICATE"
    print(blocks[0].data.length())  // decoded DER byte count
    print(encode_all([PemBlock(label: "NOTE", data: "hi".to_bytes())]))
*/

// One PEM block: its label, optional RFC 1421 style headers, and decoded body bytes.
export type PemBlock:
	// Text between `BEGIN ` and the closing dashes, such as `CERTIFICATE`.
	label: String
	// Header fields written before the body, in order; empty for modern PEM.
	headers: Map[String, String] = Map[String, String]()
	// Decoded body bytes; empty for a block with no body lines.
	data: Bytes

BEGIN := "-----BEGIN "
END := "-----END "
DASHES := "-----"

// Parses every PEM block in `text`; text outside blocks is ignored, and a text without
// blocks gives an empty list.
export fn parse(text: String) List[PemBlock]!:
	var blocks = List[PemBlock]()
	var label = ""
	var open = false
	var body = ""
	var headers = Map[String, String]()
	var in_headers = false

	for raw in text.lines():
		line := raw.trim()

		if not open:
			if (
				line.starts_with(BEGIN)
				and line.ends_with(DASHES)
				and line.length() >= 16
			):
				label = line.drop(BEGIN.length()).take(
					line.length() - BEGIN.length() - DASHES.length()
				)
				open = true
				body = ""
				headers = Map[String, String]()
				in_headers = true

			continue

		if line.starts_with(END):
			closing := line.drop(END.length())
			if closing != "{label}{DASHES}": return error(
				Error("PEM: invalid armor", kind: "EBADMSG")
			)

			data := base64_decode(body)
			if data.is_error(): return error(
				Error("PEM: invalid data", kind: "EBADMSG")
			)

			blocks.append(
				PemBlock(
					label: label.clone(), headers: headers.clone(), data: data.get()
				)
			)
			open = false
			continue

		if line.starts_with(BEGIN): return error(
			Error("PEM: invalid armor", kind: "EBADMSG")
		)

		if in_headers and line.contains(":"):
			at := line.index_of(":").get(0)
			headers.add(line.take(at).trim(), line.drop(at + 1).trim())
			continue

		in_headers = false
		body = "{body}{line}"

	if open: return error(Error("PEM: invalid armor", kind: "EBADMSG"))

	return ok(blocks)

// Encodes one block with headers first, then the body in 64-character base64 lines,
// ending with a newline.
export fn encode_block(block: PemBlock) String:
	var out = StringBuilder()
	out.append("{BEGIN}{block.label}{DASHES}\n")

	if not block.headers.is_empty():
		for entry in block.headers.entries():
			out.append("{entry.key}: {entry.value}\n")
		out.append("\n")

	body := base64_encode(block.data)
	var at = 0
	total := body.length()

	while at < total:
		stop := if at + 64 < total: at + 64 else: total
		out.append("{body.slice(at, stop).get("")}\n")
		at = stop

	out.append("{END}{block.label}{DASHES}\n")
	return out.build()

// Encodes blocks in order into one PEM text; the result parses back to equal blocks.
export fn encode_all(blocks: List[PemBlock]) String:
	var out = StringBuilder()
	for block in blocks:
		out.append(encode_block(block))
	return out.build()
