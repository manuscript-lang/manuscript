+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## NumberError {data-api-kind="Alternative"}

Errors returned for invalid numeric requests, malformed text, or out-of-range values.

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

## parse_float64 {data-api-kind="Function"}

Parses an IEEE binary64 value without first rounding to the default Float.

```manuscript
fn parse_float64(text: String) -> Result[Float64, NumberError]:
```

## parse_int {data-api-kind="Function"}

Parses an integer in a radix from 2 through 36.

```manuscript
fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]:
```

## parse_int64 {data-api-kind="Function"}

Parses a signed 64-bit integer without first passing through the default Int.

```manuscript
fn parse_int64(text: String, radix: Int) -> Result[Int64, NumberError]:
```

