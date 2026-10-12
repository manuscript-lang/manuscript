+++
title = "binary"
+++

# @std/binary.ms

Import each required symbol with `import Name from "@std/binary.ms"`.

## BinaryError

Kind: alternative.

```text
BinaryError: BinaryError
implements: Error
case InvalidInput
case OutOfRange
operation message: fn()->String
```

## read_float

Kind: fn.

```text
read_float: fn(data: Bytes, offset: Int, little_endian: Bool)->Result[Float, BinaryError]
```

## read_integer

Kind: fn.

```text
read_integer: fn(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool)->Result[Int, BinaryError]
```

## write_float

Kind: fn.

```text
write_float: fn(value: Float, little_endian: Bool)->Bytes
```

## write_integer

Kind: fn.

```text
write_integer: fn(value: Int, width: Int, signed: Bool, little_endian: Bool)->Result[Bytes, BinaryError]
```

