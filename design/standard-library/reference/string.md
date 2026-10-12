+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## at {data-api-kind="Function"}

```manuscript
at: fn(text: String, index: Int)->Optional[String]
```

## concat {data-api-kind="Function"}

```manuscript
concat: fn(text: String, values: String)->String
```

## contains {data-api-kind="Function"}

```manuscript
contains: fn(value: String, text: String)->Bool
```

## ends_with {data-api-kind="Function"}

```manuscript
ends_with: fn(value: String, suffix: String)->Bool
```

## from_scalars {data-api-kind="Function"}

```manuscript
from_scalars: fn(values: List[Int])->Result[String, LibraryError]
```

## index_of {data-api-kind="Function"}

```manuscript
index_of: fn(text: String, value: String)->Optional[Int]
```

## join {data-api-kind="Function"}

```manuscript
join: fn(parts: List[String], separator: String)->String
```

## last_index_of {data-api-kind="Function"}

```manuscript
last_index_of: fn(text: String, value: String)->Optional[Int]
```

## lower {data-api-kind="Function"}

```manuscript
lower: fn(text: String)->String
```

## normalize {data-api-kind="Function"}

```manuscript
normalize: fn(text: String, form: String, max_bytes: Int)->Result[String, LibraryError]
```

## pad_end {data-api-kind="Function"}

```manuscript
pad_end: fn(text: String, target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
```

## pad_start {data-api-kind="Function"}

```manuscript
pad_start: fn(text: String, target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
```

## repeat {data-api-kind="Function"}

```manuscript
repeat: fn(text: String, count: Int, max_bytes: Int)->Result[String, LibraryError]
```

## replace {data-api-kind="Function"}

```manuscript
replace: fn(text: String, old: String, new: String, max_replacements: Int)->String
```

## replace_all {data-api-kind="Function"}

```manuscript
replace_all: fn(text: String, old: String, new: String, max_bytes: Int)->Result[String, LibraryError]
```

## scalar_at {data-api-kind="Function"}

```manuscript
scalar_at: fn(text: String, index: Int)->Optional[Int]
```

## scalar_length {data-api-kind="Function"}

```manuscript
scalar_length: fn(text: String)->Int
```

## scalar_values {data-api-kind="Function"}

```manuscript
scalar_values: fn(text: String)->List[Int]
```

## slice {data-api-kind="Function"}

```manuscript
slice: fn(text: String, start: Int, end: Int)->String
```

## slice_scalars {data-api-kind="Function"}

```manuscript
slice_scalars: fn(text: String, start: Int, end: Int)->Result[String, LibraryError]
```

## split {data-api-kind="Function"}

```manuscript
split: fn(text: String, separator: String, max_parts: Int)->List[String]
```

## starts_with {data-api-kind="Function"}

```manuscript
starts_with: fn(value: String, prefix: String)->Bool
```

## substring {data-api-kind="Function"}

```manuscript
substring: fn(text: String, start: Int, end: Int)->String
```

## trim {data-api-kind="Function"}

```manuscript
trim: fn(text: String)->String
```

## trim_end {data-api-kind="Function"}

```manuscript
trim_end: fn(text: String)->String
```

## trim_start {data-api-kind="Function"}

```manuscript
trim_start: fn(text: String)->String
```

## upper {data-api-kind="Function"}

```manuscript
upper: fn(text: String)->String
```

