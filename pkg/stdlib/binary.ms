import Bytes from "@std/bytes.ms"

# Errors returned when a byte range or numeric representation is invalid.
export type BinaryError:
    # Integer width is unsupported; the native codec accepts only 1, 2, 4 or 8 bytes.
    case InvalidInput
    # A read crosses the byte buffer or a number cannot fit the requested signedness/width or result type.
    case OutOfRange

# Reads a 64-bit floating-point value (binary64, 8 bytes) at `offset` using the selected byte order.
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
) -> Result[Int, BinaryError]:

# Encodes a 64-bit floating-point value (binary64) as 8 bytes using the selected byte order.
export fn write_float(value: Float, little_endian: Bool) -> Bytes:

# Encodes an integer into `width` bytes, returning an error when it does not fit.
export fn write_integer(
    value: Int,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Bytes, BinaryError]:

impl Error for BinaryError:
    # Returns a binary-prefixed diagnostic without echoing source bytes or numeric input.
    fn message() -> String:
