+++
title = "json"
+++

# @std/json.ms

Import each required symbol with `import Name from "@std/json.ms"`.

## JsonEncodable {data-api-kind="Bound"}

Bound satisfied by every type that `stringify` can encode: Bool, Int, Float, String, Decimal and
BigInt; JsonValue; Optional, List and Set of encodable types; Map with String keys and encodable
values; and records or alternatives whose fields are all encodable. Functions, interfaces, resources,
Bytes, time values, Unit, Result and other standard-library types do not satisfy it. The compiler
derives the property from the type's shape, so it cannot be implemented or overridden.

```manuscript
type JsonEncodable:
```

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

Encodes any value whose type satisfies JsonEncodable as compact JSON text.

- Record fields appear in declaration order. A field of type `Optional[T]` is omitted when `none`.
- Any other `none` (a list element, a map value, the root) is `null`; `Optional[Optional[T]]` is rejected.
- An alternative case without payload is its name as a string, `"Circle"`. A case with payload is an
  object keyed by the case name whose value is an object of its labeled fields: `{"Circle":{"radius":2}}`.
- Map entries and Set elements keep insertion order; maps must have String keys.
- Int, BigInt and Decimal are written as exact decimal digits; Float uses the shortest decimal that
  parses back to the same value, and NaN or an infinity returns InvalidData.
- A JsonValue is written as it is, so parsed documents can be mixed with typed data.
- Strings are UTF-8 JSON strings; `<`, `>` and `&` are written as Unicode escapes.
- Values are read when `stringify` runs, so later mutation does not change the text. A value reachable
  from itself returns InvalidData; shared but acyclic values are written each time they appear.

`max_bytes` bounds the output; exceeding it returns LimitExceeded and a negative bound InvalidInput.

```manuscript
type Request:
    model: String
    stream: Bool
    user: Optional[String]

stringify(value: Request(model: "example", stream: true, user: none))
```

```manuscript
fn stringify[T: JsonEncodable](value: T, max_bytes: Optional[Int] = none) -> Result[String, JsonError]:
```

