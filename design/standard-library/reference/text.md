+++
title = "text"
+++

# @std/text.ms

Import each required symbol with `import Name from "@std/text.ms"`.

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

## join

Kind: fn.

```manuscript
join: fn(parts: List[String], separator: String)->String
```

## lower

Kind: fn.

```manuscript
lower: fn(text: String)->String
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

## trim

Kind: fn.

```manuscript
trim: fn(text: String)->String
```

## upper

Kind: fn.

```manuscript
upper: fn(text: String)->String
```

