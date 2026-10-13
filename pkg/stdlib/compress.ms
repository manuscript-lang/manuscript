# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# Errors returned when compressed data is unsupported, invalid, or exceeds a limit.
export type CompressionError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)

# Compresses bytes using `gzip`, `zlib`, or `deflate` at the requested level.
# `max_bytes` bounds the encoded output when supplied.
export fn compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, CompressionError]:

# Decompresses supported data and stops when the supplied output limit is reached.
export fn decompress(
    data: Bytes,
    format: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, CompressionError]:

impl Error for CompressionError:
    fn message() -> String:
