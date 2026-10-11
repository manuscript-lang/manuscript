# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export fn base64_decode(text: String, url_safe: Bool, max_bytes: Int) -> Result[Bytes, LibraryError]

export fn base64_encode(data: Bytes, url_safe: Bool) -> String

export fn hex_decode(text: String, max_bytes: Int) -> Result[Bytes, LibraryError]

export fn hex_encode(data: Bytes) -> String
