# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# Errors returned when a byte range or numeric representation is invalid.
export type BinaryError:
    case InvalidInput
    case OutOfRange

# Reads a 32-bit floating-point value at `offset` using the selected byte order.
export fn read_float(
    data: Bytes,
    offset: Int,
    little_endian: Bool
) -> Result[Float, BinaryError]:

# Reads an integer of `width` bytes. Signed values use two's-complement encoding.
export fn read_integer(
    data: Bytes,
    offset: Int,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Int64, BinaryError]:

# Encodes a 32-bit floating-point value using the selected byte order.
export fn write_float(value: Float, little_endian: Bool) -> Bytes:

# Reads an IEEE binary64 value at `offset` without rounding through Float.
export fn read_float64(
    data: Bytes,
    offset: Int,
    little_endian: Bool
) -> Result[Float64, BinaryError]:

# Encodes an IEEE binary64 value using the selected byte order.
export fn write_float64(value: Float64, little_endian: Bool) -> Bytes:

# Encodes an integer into `width` bytes, returning an error when it does not fit.
export fn write_integer(
    value: Int64,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Bytes, BinaryError]:

impl Error for BinaryError:
    fn message() -> String:
