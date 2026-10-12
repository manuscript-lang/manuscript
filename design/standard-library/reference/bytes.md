+++
title = "bytes"
+++

# @std/bytes.ms

Import each required symbol with `import Name from "@std/bytes.ms"`.

## Bytes {data-api-kind="Interface"}

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

## at {data-api-kind="Function"}

```manuscript
at: fn(data: Bytes, index: Int)->Optional[Int]
```

## contains {data-api-kind="Function"}

```manuscript
contains: fn(data: Bytes, value: Bytes)->Bool
```

## ends_with {data-api-kind="Function"}

```manuscript
ends_with: fn(data: Bytes, value: Bytes)->Bool
```

## index_of {data-api-kind="Function"}

```manuscript
index_of: fn(data: Bytes, value: Bytes)->Optional[Int]
```

## is_empty {data-api-kind="Function"}

```manuscript
is_empty: fn(data: Bytes)->Bool
```

## last_index_of {data-api-kind="Function"}

```manuscript
last_index_of: fn(data: Bytes, value: Bytes)->Optional[Int]
```

## reverse {data-api-kind="Function"}

```manuscript
reverse: fn(data: Bytes)->Bytes
```

## slice {data-api-kind="Function"}

```manuscript
slice: fn(data: Bytes, start: Int, end: Int)->Bytes
```

## starts_with {data-api-kind="Function"}

```manuscript
starts_with: fn(data: Bytes, value: Bytes)->Bool
```

## values {data-api-kind="Function"}

```manuscript
values: fn(data: Bytes)->List[Int]
```

## with_value {data-api-kind="Function"}

```manuscript
with_value: fn(data: Bytes, index: Int, value: Int)->Bytes
```

