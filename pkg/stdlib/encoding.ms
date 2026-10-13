# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# Errors returned when encoded text is invalid or exceeds a supplied byte limit.
export type EncodingError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# Decodes standard Base64 by default; set `url_safe: true` for the URL-safe alphabet.
export fn base64_decode(
    text: String,
    url_safe: Bool = false,
    max_bytes: Optional[Int64] = none
) -> Result[Bytes, EncodingError]:

# Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text.
export fn base64_encode(data: Bytes, url_safe: Bool = false) -> String:

# Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.
export fn hex_decode(
    text: String,
    max_bytes: Optional[Int64] = none
) -> Result[Bytes, EncodingError]:

# Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data: Bytes) -> String:

impl Error for EncodingError:
    fn message() -> String:
