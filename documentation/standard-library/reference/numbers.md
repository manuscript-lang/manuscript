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
    fn message() -> String:
```

## parse_float {data-api-kind="Function"}

```manuscript
fn parse_float(text: String) -> Result[Float, NumberError]:
```

## parse_int {data-api-kind="Function"}

```manuscript
fn parse_int(text: String, radix: Int) -> Result[Int, NumberError]:
```

