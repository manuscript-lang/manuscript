+++
title = "json"
+++

# @std/json.ms

Import each required symbol with `import Name from "@std/json.ms"`.

## JsonError {data-api-kind="Alternative"}

Errors returned for malformed JSON or configured input and nesting limits.

```manuscript
type JsonError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for JsonError:
    fn message() -> String:
```

### JsonError.InvalidData

JSON syntax, Unicode escapes, duplicate keys, number text or a cyclic value is invalid.

```manuscript
case InvalidData
```

### JsonError.InvalidInput

An explicit input, depth, value-count or output budget is negative.

```manuscript
case InvalidInput
```

### JsonError.LimitExceeded

The input, nesting, value count or encoded output exceeds a supplied budget.

```manuscript
case LimitExceeded
```

### JsonError.Error.message

Returns a JSON-prefixed diagnostic without echoing input text or number tokens.

```manuscript
fn message() -> String:
```

## JsonLimits {data-api-kind="Record"}

Optional bounds for JSON input bytes, nesting depth, and parsed values.

```manuscript
type JsonLimits:
    max_bytes: Optional[Int] = none
    max_depth: Optional[Int] = none
    max_values: Optional[Int] = none
```

### JsonLimits.max_bytes

Maximum UTF-8 input bytes before parsing; none adds no input-size budget.

```manuscript
max_bytes: Optional[Int] = none
```

### JsonLimits.max_depth

Maximum container nesting; a root scalar has depth zero, and a root container depth one.

```manuscript
max_depth: Optional[Int] = none
```

### JsonLimits.max_values

Maximum parsed containers and scalar values, excluding object keys; none adds no count budget.

```manuscript
max_values: Optional[Int] = none
```

## JsonValue {data-api-kind="Alternative"}

A JSON value. Number text is retained to avoid losing precision during parsing.

```manuscript
type JsonValue:
    case Null
    case BoolValue(value: Bool)
    case NumberValue(text: String)
    case StringValue(value: String)
    case ArrayValue(values: List[JsonValue])
    case ObjectValue(values: Map[String, JsonValue])
```

### JsonValue.ArrayValue

An ordered JSON array whose mutable list can be updated before serialization.

```manuscript
case ArrayValue(values: List[JsonValue])
```

### JsonValue.BoolValue

A JSON true or false value.

```manuscript
case BoolValue(value: Bool)
```

### JsonValue.Null

JSON null, represented without a payload value.

```manuscript
case Null
```

### JsonValue.NumberValue

An exact JSON number token; parsing does not coerce it into Float.

```manuscript
case NumberValue(text: String)
```

### JsonValue.ObjectValue

A JSON object retaining insertion order and rejecting duplicate keys during parsing.

```manuscript
case ObjectValue(values: Map[String, JsonValue])
```

### JsonValue.StringValue

A decoded JSON string, with escapes resolved into Unicode text.

```manuscript
case StringValue(value: String)
```

### JsonValue.ArrayValue.values

Element values in source order; nested mutable payloads retain their references.

```manuscript
values: List[JsonValue]
```

### JsonValue.BoolValue.value

The decoded boolean, without a textual representation requirement.

```manuscript
value: Bool
```

### JsonValue.NumberValue.text

Original numeric token text; stringify validates its JSON number syntax.

```manuscript
text: String
```

### JsonValue.ObjectValue.values

String-keyed members in insertion order; stringify reads their current values.

```manuscript
values: Map[String, JsonValue]
```

### JsonValue.StringValue.value

Decoded UTF-8 text, preserving scalar contents without normalization.

```manuscript
value: String
```

## parse {data-api-kind="Function"}

Parses one JSON value and applies the supplied input, depth, and value limits.

```manuscript
fn parse(text: String, limits: Optional[JsonLimits] = none) -> Result[JsonValue, JsonError]:
```

## stringify {data-api-kind="Function"}

Serializes a JSON value. `max_bytes` bounds output when supplied.

```manuscript
fn stringify(value: JsonValue, max_bytes: Optional[Int] = none) -> Result[String, JsonError]:
```

