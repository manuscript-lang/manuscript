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

Canonical composition.

```manuscript
case Nfc
```

### NormalizationForm.Nfd

Canonical decomposition.

```manuscript
case Nfd
```

### NormalizationForm.Nfkc

Compatibility composition.

```manuscript
case Nfkc
```

### NormalizationForm.Nfkd

Compatibility decomposition.

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
Mutable builder for constructing a string without repeated intermediate copies.

```manuscript
type StringBuilder:
    fn append(value: String) -> Unit:
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

## from_scalars {data-api-kind="Function"}

Builds text from Unicode scalar values. Invalid scalars return `InvalidInput`.

```manuscript
fn from_scalars(values: List[Int]) -> Result[String, StringError]:
```

