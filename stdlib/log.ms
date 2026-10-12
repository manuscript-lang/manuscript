# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import Map from "@std/collections.ms"
import Result from "@std/result.ms"
import WriteStream from "@std/io.ms"

export fn write(output: WriteStream, level: String, message: String, fields: Map[String, String], max_bytes: Int) -> Result[Unit, LibraryError]
