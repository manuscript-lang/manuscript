+++
title = "json"
+++

# @std/json.ms

Import each required symbol with `import Name from "@std/json.ms"`.

## JsonError

Kind: alternative.

```text
JsonError: JsonError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
operation message: fn()->String
```

## JsonLimits

Kind: record.

```text
JsonLimits: JsonLimits
field max_bytes: Int
field max_depth: Int
field max_values: Int
```

## JsonValue

Kind: alternative.

```text
JsonValue: JsonValue
case Null
case BoolValue(value: Bool)
case NumberValue(text: String)
case StringValue(value: String)
case ArrayValue(values: List[JsonValue])
case ObjectValue(values: Map[String, JsonValue])
```

## parse

Kind: fn.

```text
parse: fn(text: String, limits: JsonLimits)->Result[JsonValue, JsonError]
```

## stringify

Kind: fn.

```text
stringify: fn(value: JsonValue, max_bytes: Int)->Result[String, JsonError]
```

