+++
title = "binary"
+++

# @std/binary.ms

Import each required symbol with `import Name from "@std/binary.ms"`.

## read_float {data-api-kind="Function"}

```manuscript
read_float: fn(data: Bytes, offset: Int, little_endian: Bool)->Result[Float, LibraryError]
```

## read_integer {data-api-kind="Function"}

```manuscript
read_integer: fn(data: Bytes, offset: Int, width: Int, signed: Bool, little_endian: Bool)->Result[Int, LibraryError]
```

## write_float {data-api-kind="Function"}

```manuscript
write_float: fn(value: Float, little_endian: Bool)->Bytes
```

## write_integer {data-api-kind="Function"}

```manuscript
write_integer: fn(value: Int, width: Int, signed: Bool, little_endian: Bool)->Result[Bytes, LibraryError]
```

