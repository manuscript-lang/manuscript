+++
title = "bytes"
+++

# @std/bytes.ms

Import each required symbol with `import Name from "@std/bytes.ms"`.

## Bytes {data-api-kind="Native type"}

An immutable sequence of bytes. Indices and slice bounds are zero-based.

```manuscript
type Bytes:
    fn clone() -> Bytes:
    fn contains(value: Bytes) -> Bool:
    fn split(separator: Bytes, max_parts: Optional[Int] = none) -> List[Bytes]:
    fn slice(start: Int, end: Int) -> Bytes:
    fn at(index: Int) -> Optional[Int]:
    fn index_of(value: Bytes) -> Optional[Int]:
    fn last_index_of(value: Bytes) -> Optional[Int]:
    fn starts_with(value: Bytes) -> Bool:
    fn ends_with(value: Bytes) -> Bool:
    fn reversed() -> Bytes:
    fn reverse() -> Bytes:
    fn with_value(index: Int, value: Int) -> Bytes:
    fn is_empty() -> Bool:
    fn values() -> List[Int]:
    fn concat(values: Bytes) -> Bytes:
    fn length() -> Int:
    fn to_text() -> Optional[String]:
```

### Bytes.at

Returns an unsigned byte; negative indexes are relative to the end, and out-of-range indexes return `none`.

```manuscript
fn at(index: Int) -> Optional[Int]:
```

### Bytes.clone

Copies byte storage without changing the receiver.

```manuscript
fn clone() -> Bytes:
```

### Bytes.concat

Returns concatenated bytes without changing either operand.

```manuscript
fn concat(values: Bytes) -> Bytes:
```

### Bytes.contains

Tests whether `value` occurs as a byte subsequence.

```manuscript
fn contains(value: Bytes) -> Bool:
```

### Bytes.ends_with

Tests whether the receiver ends with these bytes.

```manuscript
fn ends_with(value: Bytes) -> Bool:
```

### Bytes.index_of

Returns the first matching byte offset or `none`; empty `value` matches at zero.

```manuscript
fn index_of(value: Bytes) -> Optional[Int]:
```

### Bytes.is_empty

Tests whether the receiver contains no bytes.

```manuscript
fn is_empty() -> Bool:
```

### Bytes.last_index_of

Returns the last matching byte offset or `none`; empty `value` matches at length().

```manuscript
fn last_index_of(value: Bytes) -> Optional[Int]:
```

### Bytes.length

Returns the number of bytes, not the number of Unicode characters.

```manuscript
fn length() -> Int:
```

### Bytes.reverse

Compatibility spelling for reversed; returns a copy without changing the receiver.

```manuscript
fn reverse() -> Bytes:
```

### Bytes.reversed

Returns a reversed copy without changing the receiver.

```manuscript
fn reversed() -> Bytes:
```

### Bytes.slice

Selects [start, end) in bytes; faults unless 0 <= start <= end <= length().
The immutable result may share storage with the receiver.

```manuscript
fn slice(start: Int, end: Int) -> Bytes:
```

### Bytes.split

Splits exact byte separators into a fresh list of immutable byte views.
Nonempty separators retain empty parts; empty data then yields one empty Bytes.
Omitted/none max_parts is unlimited; zero returns no parts, negatives fault.
A cap truncates parts; empty separator yields one Bytes per byte, no parts for empty data.

```manuscript
fn split(separator: Bytes, max_parts: Optional[Int] = none) -> List[Bytes]:
```

### Bytes.starts_with

Tests whether the receiver begins with these bytes.

```manuscript
fn starts_with(value: Bytes) -> Bool:
```

### Bytes.to_text

Decodes valid UTF-8 as text, or returns `none` when the bytes are invalid.

```manuscript
fn to_text() -> Optional[String]:
```

### Bytes.values

Returns a fresh mutable list of unsigned byte values; changing it leaves the Bytes unchanged.

```manuscript
fn values() -> List[Int]:
```

### Bytes.with_value

Returns a copy with one byte replaced; negative indexes are relative to the end.
An out-of-range index or a value outside 0 through 255 faults.

```manuscript
fn with_value(index: Int, value: Int) -> Bytes:
```

## BytesBuilder {data-api-kind="Native type"}

Builds a byte sequence efficiently before freezing it into an immutable value.

```manuscript
type BytesBuilder:
    fn append(value: Int) -> Unit:
    fn concat(values: Bytes) -> Unit:
    fn freeze() -> Bytes:
```

## values {data-api-kind="Function"}

Returns a fresh mutable list of byte values in the range 0 through 255, like data.values().

```manuscript
fn values(data: Bytes) -> List[Int]:
```

