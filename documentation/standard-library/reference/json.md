+++
title = "json"
+++

# @std/json.ms

Import each required symbol with `import Name from "@std/json.ms"`.

## JsonError {data-api-kind="Alternative"}

```manuscript
type JsonError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for JsonError:
    fn message() -> String
```

## JsonLimits {data-api-kind="Record"}

```manuscript
type JsonLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_values: Optional[Int] = none
```

## JsonValue {data-api-kind="Alternative"}

```manuscript
type JsonValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[JsonValue])
    case ObjectValue(values: Map[String, JsonValue])
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, limits: Optional[JsonLimits] = none) -> Result[JsonValue, JsonError]
```

## stringify {data-api-kind="Function"}

```manuscript
fn stringify(value: JsonValue, max_bytes: Optional[Int] = none) -> Result[String, JsonError]
```

