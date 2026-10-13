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

Reads a 32-bit floating-point value at `offset` using the selected byte order.

```manuscript
fn read_float(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float, BinaryError]:
```

## read_float64 {data-api-kind="Function"}

Reads an IEEE binary64 value at `offset` without rounding through Float.

```manuscript
fn read_float64(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float64, BinaryError]:
```

## read_integer {data-api-kind="Function"}

Reads an integer of `width` bytes. Signed values use two's-complement encoding.

```manuscript
fn read_integer(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Int64, BinaryError]:
```

## write_float {data-api-kind="Function"}

Encodes a 32-bit floating-point value using the selected byte order.

```manuscript
fn write_float(value: Float, little_endian: Bool) -> Bytes:
```

## write_float64 {data-api-kind="Function"}

Encodes an IEEE binary64 value using the selected byte order.

```manuscript
fn write_float64(value: Float64, little_endian: Bool) -> Bytes:
```

## write_integer {data-api-kind="Function"}

Encodes an integer into `width` bytes, returning an error when it does not fit.

```manuscript
fn write_integer(value: Int64, width: Int, signed: Bool, little_endian: Bool) -> Result[Bytes, BinaryError]:
```

