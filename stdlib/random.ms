# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export type Entropy:
    fn bytes(count: Int) -> Result[Bytes, LibraryError]

export fn secure_int(entropy: Entropy & Shareable, min: Int, max_exclusive: Int) -> Result[Int, LibraryError]

export fn uuid_v4(entropy: Entropy & Shareable) -> Result[String, LibraryError]
