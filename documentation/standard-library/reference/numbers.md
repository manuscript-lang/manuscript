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

### NumberError.InvalidData

The text does not match the numeric syntax, such as an empty string, stray characters, or digits invalid for the radix.

```manuscript
case InvalidData
```

### NumberError.InvalidInput

A radix or digit-count argument is outside its documented range.

```manuscript
case InvalidInput
```

### NumberError.OutOfRange

The text is well formed but the value does not fit, such as an integer beyond signed 64 bits or a float beyond the finite range.

```manuscript
case OutOfRange
```

### NumberError.Error.message

Returns the fixed diagnostic `number: <reason>`, such as `number: invalid data`, without echoing the input text.

```manuscript
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

