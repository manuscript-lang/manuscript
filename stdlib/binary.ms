# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export fn read_float(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float, LibraryError]

export fn read_integer(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Int, LibraryError]

export fn write_float(value: Float, little_endian: Bool) -> Bytes

export fn write_integer(value: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Bytes, LibraryError]
