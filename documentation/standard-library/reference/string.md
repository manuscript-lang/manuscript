+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## StringBuilder {data-api-kind="Native type"}

```manuscript
type StringBuilder:
    fn append(value: String) -> Unit:
    fn freeze() -> String:
```

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
    fn message() -> String:
```

## from_scalars {data-api-kind="Function"}

```manuscript
fn from_scalars(values: List[Int]) -> Result[String, StringError]:
```

