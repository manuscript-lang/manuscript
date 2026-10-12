+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## at

Kind: fn.

```text
at: fn(text: String, index: Int)->Optional[String]
```

## concat

Kind: fn.

```text
concat: fn(text: String, values: String)->String
```

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

## index_of

Kind: fn.

```text
index_of: fn(text: String, value: String)->Optional[Int]
```

## join

Kind: fn.

```text
join: fn(parts: List[String], separator: String)->String
```

## last_index_of

Kind: fn.

```text
last_index_of: fn(text: String, value: String)->Optional[Int]
```

## lower

Kind: fn.

```text
lower: fn(text: String)->String
```

## normalize

Kind: fn.

```text
normalize: fn(text: String, form: String, max_bytes: Int)->Result[String, LibraryError]
```

## pad_end

Kind: fn.

```text
pad_end: fn(text: String, target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
```

## pad_start

Kind: fn.

```text
pad_start: fn(text: String, target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
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

## replace_all

Kind: fn.

```text
replace_all: fn(text: String, old: String, new: String, max_bytes: Int)->Result[String, LibraryError]
```

## scalar_at

Kind: fn.

```text
scalar_at: fn(text: String, index: Int)->Optional[Int]
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

## slice

Kind: fn.

```text
slice: fn(text: String, start: Int, end: Int)->String
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

## substring

Kind: fn.

```text
substring: fn(text: String, start: Int, end: Int)->String
```

## trim

Kind: fn.

```text
trim: fn(text: String)->String
```

## trim_end

Kind: fn.

```text
trim_end: fn(text: String)->String
```

## trim_start

Kind: fn.

```text
trim_start: fn(text: String)->String
```

## upper

Kind: fn.

```text
upper: fn(text: String)->String
```

