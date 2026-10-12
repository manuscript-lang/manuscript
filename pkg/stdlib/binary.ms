# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

export type BinaryError:
    case InvalidInput
    case OutOfRange

export fn read_float(
    data: Bytes,
    offset: Int,
    little_endian: Bool
) -> Result[Float, BinaryError]:

export fn read_integer(
    data: Bytes,
    offset: Int,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Int, BinaryError]:

export fn write_float(value: Float, little_endian: Bool) -> Bytes:

export fn write_integer(
    value: Int,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Bytes, BinaryError]:

impl Error for BinaryError:
    fn message() -> String:
