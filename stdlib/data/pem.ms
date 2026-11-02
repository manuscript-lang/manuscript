import Bytes from "@std/bytes.ms"
import StringBuilder from "@std/string.ms"
import base64_decode, base64_encode from "@std/data/encoding.ms"

# PEM (RFC 7468) text armor: `-----BEGIN LABEL-----`, base64 body, `-----END LABEL-----`.
# Certificates, keys and CSRs travel as PEM blocks; `parse` finds every block in a text and
# `encode_all` writes blocks back with 64-column lines.
#
#     import parse, encode_all, PemBlock from "@std/data/pem.ms"
#     let blocks = parse(text).get()
#     blocks[0].label                # "CERTIFICATE"
#     blocks[0].data                 # the decoded DER bytes
#     encode_all([PemBlock(label: "NOTE", data: "hi".to_bytes())])

# Errors returned for PEM text whose armor or base64 body is malformed.
export type PemError:
    # A BEGIN line has no matching END line, or the labels differ.
    case InvalidArmor
    # A block body is not valid base64 or a header line has no colon.
    case InvalidData

# One PEM block: its label, optional RFC 1421 style headers, and decoded body bytes.
export type PemBlock:
    # Text between `BEGIN ` and the closing dashes, such as `CERTIFICATE`.
    label: String
    # Header fields written before the body, in order; empty for modern PEM.
    headers: Map[String, String] = Map[String, String]()
    # Decoded body bytes; empty for a block with no body lines.
    data: Bytes

let BEGIN = "-----BEGIN "
let END = "-----END "
let DASHES = "-----"

# Parses every PEM block in `text`; text outside blocks is ignored, and a text without blocks gives an empty list.
export fn parse(text: String) List[PemBlock]!PemError:
    var blocks = List[PemBlock]()
    var label = ""
    var open = false
    var body = ""
    var headers = Map[String, String]()
    var in_headers = false

    for raw in text.lines():
        let line = raw.trim()

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
            let closing = line.drop(END.length())
            if closing != "{label}{DASHES}": return error(PemError.InvalidArmor)

            let data = base64_decode(body)
            if data.is_error(): return error(PemError.InvalidData)

            blocks.append(
                PemBlock(
                    label: label.clone(), headers: headers.clone(), data: data.get()
                )
            )
            open = false
            continue

        if line.starts_with(BEGIN): return error(PemError.InvalidArmor)

        if in_headers and line.contains(":"):
            let at = line.index_of(":").get(0)
            headers.add(line.take(at).trim(), line.drop(at + 1).trim())
            continue

        in_headers = false
        body = "{body}{line}"

    if open: return error(PemError.InvalidArmor)

    return ok(blocks)

# Encodes one block with headers first, then the body in 64-character base64 lines, ending with a newline.
export fn encode_block(block: PemBlock) String:
    var out = StringBuilder()
    out.append("{BEGIN}{block.label}{DASHES}\n")

    if not block.headers.is_empty():
        for entry in block.headers.entries():
            out.append("{entry.key}: {entry.value}\n")
        out.append("\n")

    let body = base64_encode(block.data)
    var at = 0
    let total = body.length()

    while at < total:
        let stop = if at + 64 < total: at + 64 else: total
        out.append("{body.slice(at, stop).get("")}\n")
        at = stop

    out.append("{END}{block.label}{DASHES}\n")
    return out.build()

# Encodes blocks in order into one PEM text; the result parses back to equal blocks.
export fn encode_all(blocks: List[PemBlock]) String:
    var out = StringBuilder()
    for block in blocks:
        out.append(encode_block(block))
    return out.build()

impl Error for PemError:
    # Returns a PEM-prefixed diagnostic without echoing the input.
    fn message() String:
        match self:
            InvalidArmor: return "PEM: invalid armor"
            InvalidData: return "PEM: invalid data"
