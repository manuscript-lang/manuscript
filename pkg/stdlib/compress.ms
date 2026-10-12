# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

export type CompressionError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)

export fn compress(data: Bytes, format: String, level: Int, max_bytes: Optional[Int] = none) -> Result[Bytes, CompressionError]

export fn decompress(data: Bytes, format: String, max_bytes: Optional[Int] = none) -> Result[Bytes, CompressionError]

impl Error for CompressionError:
    fn message() -> String
