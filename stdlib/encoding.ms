import Bytes from "@std/bytes.ms"

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

# Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text.
export fn base64_encode(data: Bytes, url_safe: Bool = false) String:

# Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.
export fn hex_decode(
    text: String,
    max_bytes: Optional[Int] = none
) Result[Bytes, EncodingError]:

# Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data: Bytes) String:

impl Error for EncodingError:
    # Returns an encoding-prefixed diagnostic without echoing the encoded input.
    fn message() String:

# Encodes text as UTF-16 code units, little-endian unless `little_endian` is false (Node `utf16le`).
# No byte order mark is written.
export fn utf16_encode(text: String, little_endian: Bool = true) Bytes:

# Decodes UTF-16 bytes, little-endian unless `little_endian` is false.
# An odd length or an unpaired surrogate returns InvalidData; a negative `max_bytes` returns InvalidInput, and decoded text longer than `max_bytes` UTF-8 bytes returns LimitExceeded.
export fn utf16_decode(
    data: Bytes,
    little_endian: Bool = true,
    max_bytes: Optional[Int] = none
) Result[String, EncodingError]:

# Encodes text as ISO-8859-1, one byte per scalar. A scalar above U+00FF returns InvalidData.
export fn latin1_encode(text: String) Result[Bytes, EncodingError]:

# Decodes ISO-8859-1 bytes, mapping every byte to the scalar of the same value.
export fn latin1_decode(data: Bytes) String:

# Encodes text as 7-bit ASCII. A scalar above U+007F returns InvalidData.
export fn ascii_encode(text: String) Result[Bytes, EncodingError]:

# Decodes 7-bit ASCII bytes. A byte above 0x7F returns InvalidData.
export fn ascii_decode(data: Bytes) Result[String, EncodingError]:
