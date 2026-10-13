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

### YamlError.InvalidData

Malformed YAML or a form outside the supported parser's accepted grammar.

```manuscript
case InvalidData(line: Int, column: Int, reason: String)
```

### YamlError.InvalidInput

One of the supplied byte, depth or value-count limits is negative.

```manuscript
case InvalidInput
```

### YamlError.LimitExceeded

Parsing or validating the returned alias-expanded tree exceeds a supplied budget.

```manuscript
case LimitExceeded
```

### YamlError.UnsupportedFeature

An explicit tag, complex key or directive unsupported by this configuration parser.

```manuscript
case UnsupportedFeature(line: Int, reason: String)
```

### YamlError.InvalidData.column

One-based Unicode scalar column within that source line.

```manuscript
column: Int
```

### YamlError.InvalidData.line

One-based source line of the offending token or construct.

```manuscript
line: Int
```

### YamlError.InvalidData.reason

Parser diagnostic describing the malformed construct.

```manuscript
reason: String
```

### YamlError.UnsupportedFeature.line

One-based source line where the unsupported construct appears.

```manuscript
line: Int
```

### YamlError.UnsupportedFeature.reason

Diagnostic identifying the unsupported syntax or feature.

```manuscript
reason: String
```

### YamlError.Error.message

Formats parser positions and reason text; match the typed fields for programmatic handling.

```manuscript
fn message() -> String:
```

## YamlLimits {data-api-kind="Record"}

Optional input-byte, nesting-depth, and parsed-value limits for YAML parsing.

```manuscript
type YamlLimits:
    max_bytes: Optional[Int64]
    max_depth: Optional[Int]
    max_values: Optional[Int]
```

### YamlLimits.max_bytes

Maximum UTF-8 input bytes before line-ending normalization; none adds no budget.

```manuscript
max_bytes: Optional[Int64]
```

### YamlLimits.max_depth

Maximum value depth, including scalar leaves, with the root at one.

```manuscript
max_depth: Optional[Int]
```

### YamlLimits.max_values

Maximum containers and leaves, excluding keys; aliases count at each checked occurrence.

```manuscript
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

### YamlValue.ArrayValue

An ordered YAML sequence with ordinary mutable list storage.

```manuscript
case ArrayValue(values: List[YamlValue])
```

### YamlValue.BoolValue

A core-schema true or false value; yes and no remain strings.

```manuscript
case BoolValue(value: Bool)
```

### YamlValue.Null

YAML null, including an empty document or a plain null spelling.

```manuscript
case Null
```

### YamlValue.NumberValue

Numeric token text retained exactly instead of being coerced into Float.

```manuscript
case NumberValue(text: String)
```

### YamlValue.ObjectValue

A textual-key mapping, with insertion order and duplicate-key checks.

```manuscript
case ObjectValue(values: Map[String, YamlValue])
```

### YamlValue.StringValue

Text decoded from a quoted, plain or block scalar.

```manuscript
case StringValue(value: String)
```

### YamlValue.ArrayValue.values

Sequence entries in document order, retaining nested references.

```manuscript
values: List[YamlValue]
```

### YamlValue.BoolValue.value

The decoded boolean selected from YAML core-schema spellings.

```manuscript
value: Bool
```

### YamlValue.NumberValue.text

Original numeric spelling, including supported base prefixes and nonfinite spellings.

```manuscript
text: String
```

### YamlValue.ObjectValue.values

Decoded string keys and their values; aliases may share nested payloads.

```manuscript
values: Map[String, YamlValue]
```

### YamlValue.StringValue.value

Resulting Unicode text after escape decoding, folding and chomping.

```manuscript
value: String
```

## parse {data-api-kind="Function"}

Parses a YAML document. Unsupported YAML features and invalid input include source locations.

```manuscript
fn parse(text: String, limits: Optional[YamlLimits] = none) -> Result[YamlValue, YamlError]:
```

