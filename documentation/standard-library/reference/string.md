+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## StringBuilder {data-api-kind="Native type"}

Mutable builder for constructing a string without repeated intermediate copies.
Mutable builder for constructing a string without repeated intermediate copies.

```manuscript
type StringBuilder:
    fn append(value: String) -> Unit:
    fn freeze() -> String:
```

## StringError {data-api-kind="Alternative"}

Errors returned by Unicode scalar conversions and bounded string operations.

```manuscript
type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)
```

```manuscript
impl Error for StringError:
    fn message() -> String:
```

## from_scalars {data-api-kind="Function"}

Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.

```manuscript
fn from_scalars(values: List[Int]) -> Result[String, StringError]:
```

