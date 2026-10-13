# Canonical standard-library declarations. Implementations are native.

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
) -> Result[Bytes, EncodingError]:

# Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text.
export fn base64_encode(data: Bytes, url_safe: Bool = false) -> String:

# Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.
export fn hex_decode(
    text: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, EncodingError]:

# Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data: Bytes) -> String:

impl Error for EncodingError:
    # Returns an encoding-prefixed diagnostic without echoing the encoded input.
    fn message() -> String:
