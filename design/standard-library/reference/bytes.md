+++
title = "bytes"
+++

# @std/bytes.ms

Import each required symbol with `import Name from "@std/bytes.ms"`.

## Bytes

Kind: interface.

```manuscript
Bytes: Bytes
field values: List[Int]
operation concat: fn(values: Bytes)->Bytes
operation get: fn(index: Int)->Optional[Int]
operation length: fn()->Int
operation to_text: fn()->Optional[String]
```

## contains

Kind: fn.

```manuscript
contains: fn(data: Bytes, value: Bytes)->Bool
```

## slice

Kind: fn.

```manuscript
slice: fn(data: Bytes, start: Int, end: Int)->Bytes
```

## values

Kind: fn.

```manuscript
values: fn(data: Bytes)->List[Int]
```

