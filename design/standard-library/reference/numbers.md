+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## NumberError {data-api-kind="Alternative"}

```manuscript
type NumberError:
    case InvalidInput
    case InvalidData
    case OutOfRange
```

```manuscript
impl Error for NumberError:
    fn message() -> String
```

## format_exponential {data-api-kind="Function"}

```manuscript
fn format_exponential(value: Float, digits: Int) -> Result[String, NumberError]
```

## format_fixed {data-api-kind="Function"}

```manuscript
fn format_fixed(value: Float, digits: Int) -> Result[String, NumberError]
```

## format_float {data-api-kind="Function"}

```manuscript
fn format_float(value: Float) -> String
```

## format_int {data-api-kind="Function"}

```manuscript
fn format_int(value: Int, radix: Int) -> String
```

## format_precision {data-api-kind="Function"}

```manuscript
fn format_precision(value: Float, precision: Int) -> Result[String, NumberError]
```

## parse_float {data-api-kind="Function"}

```manuscript
fn parse_float(text: String) -> Result[Float, NumberError]
```

## parse_int {data-api-kind="Function"}

```manuscript
fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]
```

