+++
title = "binary"
+++

# @std/binary.ms

Import each required symbol with `import Name from "@std/binary.ms"`.

## read_float {data-api-kind="Function"}

```manuscript
fn read_float(data: Bytes, offset: Int, little_endian: Bool) -> Result[Float, LibraryError]
```

## read_integer {data-api-kind="Function"}

```manuscript
fn read_integer(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Int, LibraryError]
```

## write_float {data-api-kind="Function"}

```manuscript
fn write_float(value: Float, little_endian: Bool) -> Bytes
```

## write_integer {data-api-kind="Function"}

```manuscript
fn write_integer(value: Int, width: Int, signed: Bool, little_endian: Bool) -> Result[Bytes, LibraryError]
```

