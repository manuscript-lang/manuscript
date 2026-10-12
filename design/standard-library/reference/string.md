+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## at

Kind: fn.

```manuscript
at: fn(text: String, index: Int)->Optional[String]
```

## concat

Kind: fn.

```manuscript
concat: fn(text: String, values: String)->String
```

## contains

Kind: fn.

```manuscript
contains: fn(value: String, text: String)->Bool
```

## ends_with

Kind: fn.

```manuscript
ends_with: fn(value: String, suffix: String)->Bool
```

## from_scalars

Kind: fn.

```manuscript
from_scalars: fn(values: List[Int])->Result[String, LibraryError]
```

## index_of

Kind: fn.

```manuscript
index_of: fn(text: String, value: String)->Optional[Int]
```

## join

Kind: fn.

```manuscript
join: fn(parts: List[String], separator: String)->String
```

## last_index_of

Kind: fn.

```manuscript
last_index_of: fn(text: String, value: String)->Optional[Int]
```

## lower

Kind: fn.

```manuscript
lower: fn(text: String)->String
```

## normalize

Kind: fn.

```manuscript
normalize: fn(text: String, form: String, max_bytes: Int)->Result[String, LibraryError]
```

## pad_end

Kind: fn.

```manuscript
pad_end: fn(text: String, target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
```

## pad_start

Kind: fn.

```manuscript
pad_start: fn(text: String, target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
```

## repeat

Kind: fn.

```manuscript
repeat: fn(text: String, count: Int, max_bytes: Int)->Result[String, LibraryError]
```

## replace

Kind: fn.

```manuscript
replace: fn(text: String, old: String, new: String, max_replacements: Int)->String
```

## replace_all

Kind: fn.

```manuscript
replace_all: fn(text: String, old: String, new: String, max_bytes: Int)->Result[String, LibraryError]
```

## scalar_at

Kind: fn.

```manuscript
scalar_at: fn(text: String, index: Int)->Optional[Int]
```

## scalar_length

Kind: fn.

```manuscript
scalar_length: fn(text: String)->Int
```

## scalar_values

Kind: fn.

```manuscript
scalar_values: fn(text: String)->List[Int]
```

## slice

Kind: fn.

```manuscript
slice: fn(text: String, start: Int, end: Int)->String
```

## slice_scalars

Kind: fn.

```manuscript
slice_scalars: fn(text: String, start: Int, end: Int)->Result[String, LibraryError]
```

## split

Kind: fn.

```manuscript
split: fn(text: String, separator: String, max_parts: Int)->List[String]
```

## starts_with

Kind: fn.

```manuscript
starts_with: fn(value: String, prefix: String)->Bool
```

## substring

Kind: fn.

```manuscript
substring: fn(text: String, start: Int, end: Int)->String
```

## trim

Kind: fn.

```manuscript
trim: fn(text: String)->String
```

## trim_end

Kind: fn.

```manuscript
trim_end: fn(text: String)->String
```

## trim_start

Kind: fn.

```manuscript
trim_start: fn(text: String)->String
```

## upper

Kind: fn.

```manuscript
upper: fn(text: String)->String
```

