+++
title = "yaml"
+++

# @std/yaml.ms

Import each required symbol with `import Name from "@std/yaml.ms"`.

## YamlError {data-api-kind="Alternative"}

```manuscript
type YamlError:
    case InvalidInput
    case InvalidData(line: Int, column: Int, reason: String)
    case UnsupportedFeature(line: Int, reason: String)
    case LimitExceeded
```

```manuscript
impl Error for YamlError:
    fn message() -> String:
```

## YamlLimits {data-api-kind="Record"}

```manuscript
type YamlLimits:
    max_bytes: Optional[Int]
    max_depth: Optional[Int]
    max_values: Optional[Int]
```

## YamlValue {data-api-kind="Alternative"}

```manuscript
type YamlValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[YamlValue])
    case ObjectValue(values: Map[String, YamlValue])
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, limits: Optional[YamlLimits] = none) -> Result[YamlValue, YamlError]:
```

