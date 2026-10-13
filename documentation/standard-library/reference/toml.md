+++
title = "toml"
+++

# @std/toml.ms

Import each required symbol with `import Name from "@std/toml.ms"`.

## TomlError {data-api-kind="Alternative"}

Errors returned for invalid limits, malformed TOML, or exceeded resource bounds.

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

### TomlError.InvalidData

Invalid syntax, duplicate/conflicting keys, unsupported value forms or numeric range failures.

```manuscript
case InvalidData(line: Int, column: Int, reason: String)
```

### TomlError.InvalidInput

One of the supplied input-byte, depth or value-count limits is negative.

```manuscript
case InvalidInput
```

### TomlError.LimitExceeded

Input, nesting or parsed/returned value counts exceed a supplied budget.

```manuscript
case LimitExceeded
```

### TomlError.InvalidData.column

One-based Unicode scalar column after CRLF normalization.

```manuscript
column: Int
```

### TomlError.InvalidData.line

One-based line of the invalid token or conflicting construct.

```manuscript
line: Int
```

### TomlError.InvalidData.reason

Parser diagnostic describing the rejected TOML construct.

```manuscript
reason: String
```

### TomlError.Error.message

Formats the source line, scalar column and parser reason for a malformed document.

```manuscript
fn message() -> String:
```

## TomlLimits {data-api-kind="Record"}

Optional input-byte, nesting-depth, and parsed-value limits for TOML parsing.

```manuscript
type TomlLimits:
    max_bytes: Optional[Int]
    max_depth: Optional[Int]
    max_values: Optional[Int]
```

### TomlLimits.max_bytes

Maximum UTF-8 input bytes before CRLF normalization; none adds no budget.

```manuscript
max_bytes: Optional[Int]
```

### TomlLimits.max_depth

Maximum value depth, including scalar leaves and implicit tables, with the root at one.

```manuscript
max_depth: Optional[Int]
```

### TomlLimits.max_values

Maximum containers and leaves, excluding keys; checked during parsing and materialization.

```manuscript
max_values: Optional[Int]
```

## TomlValue {data-api-kind="Alternative"}

A TOML value. Date and time values retain their original TOML text.

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

### TomlValue.ArrayValue

An ordered array; elements can have different TOML value kinds.

```manuscript
case ArrayValue(values: List[TomlValue])
```

### TomlValue.BoolValue

A TOML true or false value; other capitalizations are invalid.

```manuscript
case BoolValue(value: Bool)
```

### TomlValue.DateTimeValue

A validated local/offset date or time token, retained as text.

```manuscript
case DateTimeValue(text: String)
```

### TomlValue.FloatValue

A parsed floating-point number, including TOML infinity and NaN spellings.

```manuscript
case FloatValue(value: Float)
```

### TomlValue.IntValue

A parsed whole number; out-of-range input is rejected rather than truncated.

```manuscript
case IntValue(value: Int)
```

### TomlValue.StringValue

Text decoded from TOML basic or literal string syntax.

```manuscript
case StringValue(value: String)
```

### TomlValue.TableValue

An insertion-ordered table; parse returns this case even for an empty document.

```manuscript
case TableValue(values: Map[String, TomlValue])
```

### TomlValue.ArrayValue.values

Element values in document order, with ordinary mutable list storage.

```manuscript
values: List[TomlValue]
```

### TomlValue.BoolValue.value

The decoded boolean from the lowercase TOML token.

```manuscript
value: Bool
```

### TomlValue.DateTimeValue.text

Original accepted TOML date/time spelling, without a timezone conversion.

```manuscript
text: String
```

### TomlValue.FloatValue.value

Numeric value of the accepted floating token, preserving signed zero.

```manuscript
value: Float
```

### TomlValue.IntValue.value

Exact signed integer value of the accepted TOML numeric token.

```manuscript
value: Int
```

### TomlValue.StringValue.value

Unicode contents after the applicable escapes and multiline rules.

```manuscript
value: String
```

### TomlValue.TableValue.values

String-keyed entries produced by assignments, dotted keys and table headers.

```manuscript
values: Map[String, TomlValue]
```

## parse {data-api-kind="Function"}

Parses a TOML document into a table value and reports source line and column on invalid input.

```manuscript
fn parse(text: String, limits: Optional[TomlLimits] = none) -> Result[TomlValue, TomlError]:
```

