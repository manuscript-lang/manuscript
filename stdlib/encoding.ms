import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {from_scalars, StringBuilder} from "@std/string.ms"
import {range} from "@std/collections.ms"

# Errors returned when encoded text is invalid or exceeds a supplied byte limit.
export type EncodingError:
    # A supplied decoded-output byte budget is negative.
    case InvalidInput
    # Hexadecimal digits or strict padded Base64 syntax/characters are invalid.
    case InvalidData
    # The decoded byte count exceeds the supplied output budget.
    case LimitExceeded

# Decodes standard Base64 by default; set `url_safe: true` for the URL-safe alphabet.
export fn base64_decode(
    text: String,
    url_safe: Bool = false,
    max_bytes: Optional[Int] = none
) Result[Bytes, EncodingError]:
    let limit = budget(max_bytes)
    if limit < 0: return error(EncodingError.InvalidInput)

    let bytes = text.to_bytes().values()
    let length = bytes.length()
    var padding = 0
    var tail = length

    while tail > 0 and bytes[tail - 1] == 61:
        padding += 1
        tail -= 1

    for byte in bytes:
        if byte == 9 or byte == 10 or byte == 13 or byte == 32: return error(
            EncodingError.InvalidData
        )

    if padding > 2 or length % 4 != 0: return error(EncodingError.InvalidData)
    if length / 4 * 3 - padding > limit: return error(EncodingError.LimitExceeded)

    var out = BytesBuilder()
    let quads = length / 4

    for quad in range(0, quads):
        var pad = 0
        if quad + 1 == quads: pad = padding
        var value = 0

        for offset in range(0, 4):
            let byte = bytes[quad * 4 + offset]
            var digit = 0

            if offset >= 4 - pad:
                if byte != 61: return error(EncodingError.InvalidData)
            else:
                digit = base64_digit(byte, url_safe)
                if digit < 0: return error(EncodingError.InvalidData)

            value = value * 64 + digit

        if pad == 1 and value % 256 != 0: return error(EncodingError.InvalidData)
        if pad == 2 and value % 65536 != 0: return error(EncodingError.InvalidData)

        out.append(value / 65536 % 256)
        if pad < 2: out.append(value / 256 % 256)
        if pad < 1: out.append(value % 256)

    return ok(out.freeze())

# Value of a Base64 digit in the chosen alphabet, or -1.
fn base64_digit(byte: Int, url_safe: Bool) Int:
    if byte >= 65 and byte <= 90: return byte - 65
    if byte >= 97 and byte <= 122: return byte - 71
    if byte >= 48 and byte <= 57: return byte + 4
    if url_safe:
        if byte == 45: return 62
        if byte == 95: return 63
        return -1

    if byte == 43: return 62
    if byte == 47: return 63
    return -1

# One Base64 digit as text.
fn base64_char(value: Int, url_safe: Bool) String:
    if value < 26: return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".get(value)
    if value < 52: return "abcdefghijklmnopqrstuvwxyz".get(value - 26)
    if value < 62: return "0123456789".get(value - 52)
    if value == 62:
        if url_safe: return "-"
        return "+"

    if url_safe: return "_"
    return "/"

# The budget as a count, with no budget as a very large one and a negative budget as -1.
fn budget(max_bytes: Optional[Int]) Int:
    if let limit = max_bytes: return limit
    return 9223372036854775807

# Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text.
export fn base64_encode(data: Bytes, url_safe: Bool = false) String:
    var out = StringBuilder()
    let bytes = data.values()
    let length = bytes.length()
    var index = 0

    while index < length:
        let remaining = length - index
        var second = 0
        var third = 0
        if remaining > 1: second = bytes[index + 1]
        if remaining > 2: third = bytes[index + 2]
        let value = bytes[index] * 65536 + second * 256 + third
        out.append(base64_char(value / 262144 % 64, url_safe))
        out.append(base64_char(value / 4096 % 64, url_safe))
        if remaining > 1: out.append(base64_char(value / 64 % 64, url_safe))
        else: out.append("=")
        if remaining > 2: out.append(base64_char(value % 64, url_safe))
        else: out.append("=")
        index += 3

    return out.freeze()

# Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.
export fn hex_decode(
    text: String,
    max_bytes: Optional[Int] = none
) Result[Bytes, EncodingError]:
    let limit = budget(max_bytes)
    if limit < 0: return error(EncodingError.InvalidInput)

    let digits = text.to_bytes().values()
    let length = digits.length()
    if length / 2 > limit: return error(EncodingError.LimitExceeded)
    if length % 2 != 0: return error(EncodingError.InvalidData)

    var out = BytesBuilder()

    for pair in range(0, length / 2):
        let high = hex_digit(digits[pair * 2])
        let low = hex_digit(digits[pair * 2 + 1])
        if high < 0 or low < 0: return error(EncodingError.InvalidData)
        out.append(high * 16 + low)

    return ok(out.freeze())

# Value of a hexadecimal digit of either case, or -1.
fn hex_digit(byte: Int) Int:
    if byte >= 48 and byte <= 57: return byte - 48
    if byte >= 97 and byte <= 102: return byte - 87
    if byte >= 65 and byte <= 70: return byte - 55
    return -1

# Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data: Bytes) String:
    var out = StringBuilder()

    for byte in data.values():
        out.append("0123456789abcdef".get(byte / 16))
        out.append("0123456789abcdef".get(byte % 16))

    return out.freeze()

impl Error for EncodingError:
    # Returns an encoding-prefixed diagnostic without echoing the encoded input.
    fn message() String:
        match self:
            InvalidInput: return "encoding: invalid input"
            InvalidData: return "encoding: invalid data"
            LimitExceeded: return "encoding: limit exceeded"

# Encodes text as UTF-16 code units, little-endian unless `little_endian` is false (Node `utf16le`).
# No byte order mark is written.
export fn utf16_encode(text: String, little_endian: Bool = true) Bytes:
    var out = BytesBuilder()

    for scalar in text.scalar_values():
        if scalar < 65536:
            append_unit(var out, scalar, little_endian)
        else:
            let offset = scalar - 65536
            append_unit(var out, 55296 + offset / 1024, little_endian)
            append_unit(var out, 56320 + offset % 1024, little_endian)

    return out.freeze()

fn append_unit(var out: BytesBuilder, code: Int, little_endian: Bool) Unit:
    if little_endian:
        out.append(code % 256)
        out.append(code / 256)
    else:
        out.append(code / 256)
        out.append(code % 256)

# UTF-8 byte length of one scalar.
fn utf8_length(scalar: Int) Int:
    if scalar < 128: return 1
    if scalar < 2048: return 2
    if scalar < 65536: return 3
    return 4

fn text_of(scalars: List[Int]) String:
    if let text = from_scalars(scalars): return text
    return ""

# Decodes UTF-16 bytes, little-endian unless `little_endian` is false.
# An odd length or an unpaired surrogate returns InvalidData; a negative `max_bytes` returns InvalidInput, and decoded text longer than `max_bytes` UTF-8 bytes returns LimitExceeded.
export fn utf16_decode(
    data: Bytes,
    little_endian: Bool = true,
    max_bytes: Optional[Int] = none
) Result[String, EncodingError]:
    let limit = budget(max_bytes)
    if limit < 0: return error(EncodingError.InvalidInput)

    let bytes = data.values()
    if bytes.length() % 2 != 0: return error(EncodingError.InvalidData)

    var units = List[Int]()

    for pair in range(0, bytes.length() / 2):
        if little_endian: units.append(bytes[pair * 2] + bytes[pair * 2 + 1] * 256)
        else: units.append(bytes[pair * 2] * 256 + bytes[pair * 2 + 1])

    var scalars = List[Int]()
    var size = 0
    var index = 0

    while index < units.length():
        let code = units[index]
        var scalar = code
        index += 1

        if code >= 56320 and code < 57344: return error(EncodingError.InvalidData)

        if code >= 55296 and code < 56320:
            if index >= units.length(): return error(EncodingError.InvalidData)
            let next = units[index]
            if next < 56320 or next >= 57344: return error(EncodingError.InvalidData)
            scalar = 65536 + (code - 55296) * 1024 + (next - 56320)
            index += 1

        size += utf8_length(scalar)
        if size > limit: return error(EncodingError.LimitExceeded)
        scalars.append(scalar)

    return ok(text_of(scalars))

# Encodes text as ISO-8859-1, one byte per scalar. A scalar above U+00FF returns InvalidData.
export fn latin1_encode(text: String) Result[Bytes, EncodingError]:
    return narrow(text, 255)

fn narrow(text: String, maximum: Int) Result[Bytes, EncodingError]:
    var out = BytesBuilder()

    for scalar in text.scalar_values():
        if scalar > maximum: return error(EncodingError.InvalidData)
        out.append(scalar)

    return ok(out.freeze())

# Decodes ISO-8859-1 bytes, mapping every byte to the scalar of the same value.
export fn latin1_decode(data: Bytes) String:
    return text_of(data.values())

# Encodes text as 7-bit ASCII. A scalar above U+007F returns InvalidData.
export fn ascii_encode(text: String) Result[Bytes, EncodingError]:
    return narrow(text, 127)

# Decodes 7-bit ASCII bytes. A byte above 0x7F returns InvalidData.
export fn ascii_decode(data: Bytes) Result[String, EncodingError]:
    let bytes = data.values()

    for byte in bytes:
        if byte > 127: return error(EncodingError.InvalidData)

    return ok(text_of(bytes))
