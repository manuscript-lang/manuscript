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
operation at: fn(index: Int)->Optional[Int]
operation concat: fn(values: Bytes)->Bytes
operation contains: fn(value: Bytes)->Bool
operation ends_with: fn(value: Bytes)->Bool
operation get: fn(index: Int)->Optional[Int]
operation index_of: fn(value: Bytes)->Optional[Int]
operation is_empty: fn()->Bool
operation last_index_of: fn(value: Bytes)->Optional[Int]
operation length: fn()->Int
operation reverse: fn()->Bytes
operation slice: fn(start: Int, end: Int)->Bytes
operation starts_with: fn(value: Bytes)->Bool
operation to_text: fn()->Optional[String]
operation with_value: fn(index: Int, value: Int)->Bytes
```

## at

Kind: fn.

```manuscript
at: fn(data: Bytes, index: Int)->Optional[Int]
```

## contains

Kind: fn.

```manuscript
contains: fn(data: Bytes, value: Bytes)->Bool
```

## ends_with

Kind: fn.

```manuscript
ends_with: fn(data: Bytes, value: Bytes)->Bool
```

## index_of

Kind: fn.

```manuscript
index_of: fn(data: Bytes, value: Bytes)->Optional[Int]
```

## is_empty

Kind: fn.

```manuscript
is_empty: fn(data: Bytes)->Bool
```

## last_index_of

Kind: fn.

```manuscript
last_index_of: fn(data: Bytes, value: Bytes)->Optional[Int]
```

## reverse

Kind: fn.

```manuscript
reverse: fn(data: Bytes)->Bytes
```

## slice

Kind: fn.

```manuscript
slice: fn(data: Bytes, start: Int, end: Int)->Bytes
```

## starts_with

Kind: fn.

```manuscript
starts_with: fn(data: Bytes, value: Bytes)->Bool
```

## values

Kind: fn.

```manuscript
values: fn(data: Bytes)->List[Int]
```

## with_value

Kind: fn.

```manuscript
with_value: fn(data: Bytes, index: Int, value: Int)->Bytes
```

