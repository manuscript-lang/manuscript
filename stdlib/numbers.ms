# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export fn format_float(value: Float) -> String

export fn format_int(value: Int, radix: Int) -> String

export fn parse_float(text: String) -> Result[Float, LibraryError]

export fn parse_int(text: String, radix: Int) -> Result[Int, LibraryError]
