import (
	Bytes from "@std/bytes.ms",
	base64_decode, base64_encode from "@std/data/encoding.ms",
)

/*
PEM (RFC 7468) text armor: `-----BEGIN LABEL-----`, base64 body, `-----END LABEL-----`.
Certificates, keys and CSRs travel as PEM blocks; `parse` finds every block in a text and
`encode_all` writes blocks back with 64-column lines.

<!-- manuscript-example: {"mode":"fragment","given":["text: String"]} -->
```manuscript
import PemBlock, encode_all, parse from "@std/data/pem.ms"
blocks := parse(text)?
print(blocks[0].label)         // "CERTIFICATE"
print(blocks[0].data.length())  // decoded DER byte count
print(encode_all([PemBlock(label: "NOTE", data: "hi".to_bytes())]))
```
*/

// One PEM block: its label, optional RFC 1421 style headers, and decoded body bytes.
export type PemBlock:
	// Text between `BEGIN ` and the closing dashes, such as `CERTIFICATE`.
	label: String
	// Decoded body bytes; empty for a block with no body lines.
	data: Bytes
	// Header fields written before the body, in order; empty for modern PEM.
	headers: Map[String, String] = Map[String, String]()

BEGIN := "-----BEGIN "
END := "-----END "
DASHES := "-----"

// Parses every PEM block in `text`. Text outside blocks is ignored, and a text without
// blocks gives an empty list. Mismatched, nested or unterminated armor, or a body that
// is not valid Base64, returns an `Error` with kind `EBADMSG`.
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
				label = line.view(
					BEGIN.length(),
					line.length() - DASHES.length(),
				).clone()
				open = true
				body = ""
				headers = Map[String, String]()
				in_headers = true

			continue

		if line.starts_with(END):
			closing := line.view(END.length(), line.length())
			if closing != f"{label}{DASHES}": return error(
				Error("PEM: invalid armor", kind: "EBADMSG")
			)

			data := base64_decode(body)
			if data.is_error(): return error(
				Error("PEM: invalid data", kind: "EBADMSG")
			)

			blocks.append(
				PemBlock(
					label: label.clone(),
					headers: headers.clone(),
					data: data.get(),
				)
			)
			open = false
			continue

		if line.starts_with(BEGIN): return error(
			Error("PEM: invalid armor", kind: "EBADMSG")
		)

		if in_headers and line.contains(":"):
			at := line.index_of(":") or 0
			headers.add(
				line.view(0, at).trim().clone(),
				line.view(at + 1, line.length()).trim().clone(),
			)
			continue

		in_headers = false
		body = f"{body}{line}"

	if open: return error(Error("PEM: invalid armor", kind: "EBADMSG"))

	return ok(blocks)

// Encodes one block with headers first, then the body in 64-character base64 lines,
// ending with a newline.
export fn encode_block(block: PemBlock) String:
	var out = ""
	out += f"{BEGIN}{block.label}{DASHES}\n"

	if not block.headers.is_empty():
		for entry in block.headers.entries():
			out += f"{entry.key}: {entry.value}\n"
		out += "\n"

	body := base64_encode(block.data)
	var at = 0
	total := body.length()

	while at < total:
		stop := if at + 64 < total: at + 64 else: total
		out += f"{body.slice(at, stop)}\n"
		at = stop

	out += f"{END}{block.label}{DASHES}\n"
	return out

// Encodes blocks in order into one PEM text; the result parses back to equal blocks.
export fn encode_all(blocks: List[PemBlock]) String:
	var out = ""
	for block in blocks:
		out += encode_block(block)
	return out
