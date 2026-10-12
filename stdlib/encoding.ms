# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

export type EncodingError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export fn base64_decode(text: String, url_safe: Bool, max_bytes: Int) -> Result[Bytes, EncodingError]

export fn base64_encode(data: Bytes, url_safe: Bool) -> String

export fn hex_decode(text: String, max_bytes: Int) -> Result[Bytes, EncodingError]

export fn hex_encode(data: Bytes) -> String

impl Error for EncodingError:
    fn message() -> String
