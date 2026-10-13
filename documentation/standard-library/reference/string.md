+++
title = "string"
+++

# @std/string.ms

Import each required symbol with `import Name from "@std/string.ms"`.

## NormalizationForm {data-api-kind="Alternative"}

The four Unicode normalization forms, selected without runtime string spelling errors.

```manuscript
type NormalizationForm:
    case Nfc
    case Nfd
    case Nfkc
    case Nfkd
    fn normalize(text: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
```

### NormalizationForm.Nfc

Canonical decomposition followed by canonical recomposition where Unicode permits it.

```manuscript
case Nfc
```

### NormalizationForm.Nfd

Canonical decomposition with combining marks placed in canonical order.

```manuscript
case Nfd
```

### NormalizationForm.Nfkc

Compatibility decomposition followed by canonical recomposition where Unicode permits it.

```manuscript
case Nfkc
```

### NormalizationForm.Nfkd

Compatibility decomposition with combining marks placed in canonical order.

```manuscript
case Nfkd
```

### NormalizationForm.normalize

Normalizes text with the existing String.normalize budgets and StringError cases.
Omission or none adds no output budget; a supplied budget counts UTF-8 bytes.

```manuscript
fn normalize(text: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
```

## StringBuilder {data-api-kind="Native type"}

Mutable builder for constructing a string without repeated intermediate copies.

```manuscript
type StringBuilder:
    fn append(value: String) -> Unit:
    fn freeze() -> String:
```

### StringBuilder.append

Appends the supplied text in order; mutation after freeze raises a sealed-builder fault.

```manuscript
fn append(value: String) -> Unit:
```

### StringBuilder.freeze

Seals the builder and returns immutable text; repeated freeze returns the same text value.

```manuscript
fn freeze() -> String:
```

## StringError {data-api-kind="Alternative"}

Errors returned by Unicode scalar conversions and bounded string operations.

```manuscript
type StringError:
    case InvalidInput
    case OutOfRange
    case LimitExceeded
    case Failed(message: String)
```

```manuscript
impl Error for StringError:
    fn message() -> String:
```

### StringError.Failed

A string-domain failure with an explicit diagnostic supplied by an implementation.

```manuscript
case Failed(message: String)
```

### StringError.InvalidInput

Scalar values, normalization form or a supplied repeat/padding/output budget is invalid.

```manuscript
case InvalidInput
```

### StringError.LimitExceeded

UTF-8 output exceeds a supplied byte budget or the native string allocation limit.

```manuscript
case LimitExceeded
```

### StringError.OutOfRange

A strict scalar slice bound lies outside the string or its range is inverted.

```manuscript
case OutOfRange
```

### StringError.Failed.message

Original diagnostic text, returned unchanged by message().

```manuscript
message: String
```

### StringError.Error.message

Returns original Failed text, or a string-prefixed diagnostic for other cases.

```manuscript
fn message() -> String:
```

## from_scalars {data-api-kind="Function"}

Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.

```manuscript
fn from_scalars(values: List[Int]) -> Result[String, StringError]:
```

