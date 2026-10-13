+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## NumberError {data-api-kind="Alternative"}

Errors returned when numeric text is malformed or outside the target range.

```manuscript
type NumberError:
    case InvalidInput
    case InvalidData
    case OutOfRange
```

```manuscript
impl Error for NumberError:
    fn message() -> String:
```

## parse_float {data-api-kind="Function"}

Parses a decimal floating-point number using Manuscript's numeric syntax.

```manuscript
fn parse_float(text: String) -> Result[Float, NumberError]:
```

## parse_int {data-api-kind="Function"}

Parses an integer in a radix from 2 through 36.

```manuscript
fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]:
```

