+++
title = "json"
+++

# @std/json.ms

Import each required symbol with `import Name from "@std/json.ms"`.

## JsonLimits {data-api-kind="Record"}

```manuscript
JsonLimits: JsonLimits
field max_bytes: Int
field max_depth: Int
field max_values: Int
```

## JsonValue {data-api-kind="Alternative"}

```manuscript
JsonValue: JsonValue
case Null
case BoolValue(value: Bool)
case NumberValue(text: String)
case StringValue(value: String)
case ArrayValue(values: List[JsonValue])
case ObjectValue(values: Map[String, JsonValue])
```

## parse {data-api-kind="Function"}

```manuscript
parse: fn(text: String, limits: JsonLimits)->Result[JsonValue, LibraryError]
```

## stringify {data-api-kind="Function"}

```manuscript
stringify: fn(value: JsonValue, max_bytes: Int)->Result[String, LibraryError]
```

