+++
title = "yaml"
+++

# @std/yaml.ms

Import each required symbol with `import Name from "@std/yaml.ms"`.

## YamlError {data-api-kind="Alternative"}

Errors returned for malformed YAML, unsupported features, or exceeded resource limits.

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

Optional input-byte, nesting-depth, and parsed-value limits for YAML parsing.

```manuscript
type YamlLimits:
    max_bytes: Optional[Int]
    max_depth: Optional[Int]
    max_values: Optional[Int]
```

## YamlValue {data-api-kind="Alternative"}

A YAML value represented as null, boolean, number text, string, array, or object.

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

Parses a YAML document. Unsupported YAML features and invalid input include source locations.

```manuscript
fn parse(text: String, limits: Optional[YamlLimits] = none) -> Result[YamlValue, YamlError]:
```

