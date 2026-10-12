# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

# Errors returned when encoded text is invalid or exceeds a supplied byte limit.
export type EncodingError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# Decodes standard or URL-safe Base64 text into bytes.
export fn base64_decode(
    text: String,
    url_safe: Bool,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, EncodingError]:

# Encodes bytes as standard or URL-safe Base64 text.
export fn base64_encode(data: Bytes, url_safe: Bool) -> String:

# Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.
export fn hex_decode(
    text: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, EncodingError]:

# Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data: Bytes) -> String:

impl Error for EncodingError:
    fn message() -> String:
