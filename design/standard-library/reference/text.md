+++
title = "text"
+++

# @std/text.ms

Import each required symbol with `import Name from "@std/text.ms"`.

## contains

Kind: fn.

```text
contains: fn(value: String, text: String)->Bool
```

## ends_with

Kind: fn.

```text
ends_with: fn(value: String, suffix: String)->Bool
```

## from_scalars

Kind: fn.

```text
from_scalars: fn(values: List[Int])->Result[String, LibraryError]
```

## join

Kind: fn.

```text
join: fn(parts: List[String], separator: String)->String
```

## lower

Kind: fn.

```text
lower: fn(text: String)->String
```

## repeat

Kind: fn.

```text
repeat: fn(text: String, count: Int, max_bytes: Int)->Result[String, LibraryError]
```

## replace

Kind: fn.

```text
replace: fn(text: String, old: String, new: String, max_replacements: Int)->String
```

## scalar_length

Kind: fn.

```text
scalar_length: fn(text: String)->Int
```

## scalar_values

Kind: fn.

```text
scalar_values: fn(text: String)->List[Int]
```

## slice_scalars

Kind: fn.

```text
slice_scalars: fn(text: String, start: Int, end: Int)->Result[String, LibraryError]
```

## split

Kind: fn.

```text
split: fn(text: String, separator: String, max_parts: Int)->List[String]
```

## starts_with

Kind: fn.

```text
starts_with: fn(value: String, prefix: String)->Bool
```

## trim

Kind: fn.

```text
trim: fn(text: String)->String
```

## upper

Kind: fn.

```text
upper: fn(text: String)->String
```

