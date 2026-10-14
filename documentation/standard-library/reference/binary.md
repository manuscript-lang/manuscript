+++
title = "binary"
+++

# @std/binary.ms

Import each required symbol with `import Name from "@std/binary.ms"`.

## BinaryError {data-api-kind="Alternative"}

Errors returned when a byte range or numeric representation is invalid.

```manuscript
type BinaryError:
    case InvalidInput
    case OutOfRange
```

```manuscript
impl Error for BinaryError:
    fn message() -> String:
```

### BinaryError.InvalidInput

Integer width is unsupported; the native codec accepts only 1, 2, 4 or 8 bytes.

```manuscript
case InvalidInput
```

### BinaryError.OutOfRange

A read crosses the byte buffer or a number cannot fit the requested signedness/width or result type.

```manuscript
case OutOfRange
```

### BinaryError.Error.message

Returns a binary-prefixed diagnostic without echoing source bytes or numeric input.

```manuscript
fn message() -> String:
```

## read_float {data-api-kind="Function"}

Reads a 64-bit floating-point value (binary64, 8 bytes) at `offset` using the selected byte order.

```manuscript
fn read_float(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float, BinaryError]:
```

## read_integer {data-api-kind="Function"}

Reads an integer of `width` bytes. Signed values use two's-complement encoding.

```manuscript
fn read_integer(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Int, BinaryError]:
```

## write_float {data-api-kind="Function"}

Encodes a 64-bit floating-point value (binary64) as 8 bytes using the selected byte order.

```manuscript
fn write_float(value: Float, little_endian: Bool) -> Bytes:
```

## write_integer {data-api-kind="Function"}

Encodes an integer into `width` bytes, returning an error when it does not fit.

```manuscript
fn write_integer(value: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Bytes, BinaryError]:
```

