+++
title = "toml"
+++

# @std/toml.ms

Import each required symbol with `import Name from "@std/toml.ms"`.

## TomlError {data-api-kind="Alternative"}

```manuscript
type TomlError:
    case InvalidInput
    case InvalidData(line: Int, column: Int, reason: String)
    case LimitExceeded
```

```manuscript
impl Error for TomlError:
    fn message() -> String:
```

## TomlLimits {data-api-kind="Record"}

```manuscript
type TomlLimits:
    max_bytes: Optional[Int]
    max_depth: Optional[Int]
    max_values: Optional[Int]
```

## TomlValue {data-api-kind="Alternative"}

```manuscript
type TomlValue:
    case StringValue(value: String)
    case IntValue(value: Int)
    case FloatValue(value: Float)
    case BoolValue(value: Bool)
    case DateTimeValue(text: String)
    case ArrayValue(values: List[TomlValue])
    case TableValue(values: Map[String, TomlValue])
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, limits: Optional[TomlLimits] = none) -> Result[TomlValue, TomlError]:
```

