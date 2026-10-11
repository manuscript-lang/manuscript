# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export fn compress(data: Bytes, format: String, level: Int, max_bytes: Int) -> Result[Bytes, LibraryError]

export fn decompress(data: Bytes, format: String, max_bytes: Int) -> Result[Bytes, LibraryError]
