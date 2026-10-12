+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## StringError {data-api-kind="Alternative"}

```manuscript
type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)
```

```manuscript
impl Error for StringError:
    fn message() -> String
```

## at {data-api-kind="Function"}

```manuscript
fn at(text: String, index: Int) -> Optional[String]
```

## concat {data-api-kind="Function"}

```manuscript
fn concat(text: String, values: String) -> String
```

## contains {data-api-kind="Function"}

```manuscript
fn contains(value: String, text: String) -> Bool
```

## ends_with {data-api-kind="Function"}

```manuscript
fn ends_with(value: String, suffix: String) -> Bool
```

## from_scalars {data-api-kind="Function"}

```manuscript
fn from_scalars(values: List[Int]) -> Result[String, StringError]
```

## index_of {data-api-kind="Function"}

```manuscript
fn index_of(text: String, value: String) -> Optional[Int]
```

## join {data-api-kind="Function"}

```manuscript
fn join(parts: List[String], separator: String) -> String
```

## last_index_of {data-api-kind="Function"}

```manuscript
fn last_index_of(text: String, value: String) -> Optional[Int]
```

## lower {data-api-kind="Function"}

```manuscript
fn lower(text: String) -> String
```

## normalize {data-api-kind="Function"}

```manuscript
fn normalize(text: String, form: String, max_bytes: Int) -> Result[String, StringError]
```

## pad_end {data-api-kind="Function"}

```manuscript
fn pad_end(text: String, target_length: Int, padding: String, max_bytes: Int) -> Result[String, StringError]
```

## pad_start {data-api-kind="Function"}

```manuscript
fn pad_start(text: String, target_length: Int, padding: String, max_bytes: Int) -> Result[String, StringError]
```

## repeat {data-api-kind="Function"}

```manuscript
fn repeat(text: String, count: Int, max_bytes: Int) -> Result[String, StringError]
```

## replace {data-api-kind="Function"}

```manuscript
fn replace(text: String, old: String, new: String, max_replacements: Int) -> String
```

## replace_all {data-api-kind="Function"}

```manuscript
fn replace_all(text: String, old: String, new: String, max_bytes: Int) -> Result[String, StringError]
```

## scalar_at {data-api-kind="Function"}

```manuscript
fn scalar_at(text: String, index: Int) -> Optional[Int]
```

## scalar_length {data-api-kind="Function"}

```manuscript
fn scalar_length(text: String) -> Int
```

## scalar_values {data-api-kind="Function"}

```manuscript
fn scalar_values(text: String) -> List[Int]
```

## slice {data-api-kind="Function"}

```manuscript
fn slice(text: String, start: Int, end: Int) -> String
```

## slice_scalars {data-api-kind="Function"}

```manuscript
fn slice_scalars(text: String, start: Int, end: Int) -> Result[String, StringError]
```

## split {data-api-kind="Function"}

```manuscript
fn split(text: String, separator: String, max_parts: Int) -> List[String]
```

## starts_with {data-api-kind="Function"}

```manuscript
fn starts_with(value: String, prefix: String) -> Bool
```

## substring {data-api-kind="Function"}

```manuscript
fn substring(text: String, start: Int, end: Int) -> String
```

## trim {data-api-kind="Function"}

```manuscript
fn trim(text: String) -> String
```

## trim_end {data-api-kind="Function"}

```manuscript
fn trim_end(text: String) -> String
```

## trim_start {data-api-kind="Function"}

```manuscript
fn trim_start(text: String) -> String
```

## upper {data-api-kind="Function"}

```manuscript
fn upper(text: String) -> String
```

