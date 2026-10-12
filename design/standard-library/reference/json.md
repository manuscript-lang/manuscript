+++
title = "json"
+++

# @std/json.ms

Import each required symbol with `import Name from "@std/json.ms"`.

## JsonLimits

Kind: record.

```manuscript
JsonLimits: JsonLimits
field max_bytes: Int
field max_depth: Int
field max_values: Int
```

## JsonValue

Kind: alternative.

```manuscript
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

```manuscript
parse: fn(text: String, limits: JsonLimits)->Result[JsonValue, LibraryError]
```

## stringify

Kind: fn.

```manuscript
stringify: fn(value: JsonValue, max_bytes: Int)->Result[String, LibraryError]
```

