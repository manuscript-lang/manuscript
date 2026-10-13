# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# Errors returned when compressed data is unsupported, invalid, or exceeds a limit.
export type CompressionError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)

# Compresses using exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive).
# Other formats return Unsupported; level must be 0..9 (0 stores data), else InvalidInput.
# `max_bytes` bounds the encoded output when supplied.
export fn compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, CompressionError]:

# Decompresses exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive); others return Unsupported.
# Stops when the supplied output limit is reached.
export fn decompress(
    data: Bytes,
    format: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, CompressionError]:

impl Error for CompressionError:
    fn message() -> String:
