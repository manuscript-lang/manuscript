+++
title = "Strings and bytes"
weight = 4
+++

# Strings and bytes

`String` is immutable, always valid UTF-8, and needs no import. `Bytes` is immutable raw data; import it from `@std/bytes.ms` to name the type.

## String literals

A literal is delimited by `"` and fits on one source line, interpolations included. Raw newlines and control characters U+0000 to U+001F are rejected; other Unicode appears directly. There are no single-quoted, raw, multiline, or byte literals.

| Escape | Value |
| --- | --- |
| `\"` | Double quote |
| `\\` | Backslash |
| `\n` | LF, U+000A |
| `\r` | CR, U+000D |
| `\t` | Tab, U+0009 |
| `\{`, `\}` | Literal opening/closing brace |
| `\u{H}` | Unicode scalar with one to six hexadecimal digits H |

Hex digits may be either case. Scalars above U+10FFFF, surrogates U+D800 to U+DFFF, unknown escapes, an unescaped closing brace, and unterminated literals are compile errors. `\u{0}` is a valid null character.

```manuscript
let quote = "She said \"hello\"."
let template = "Literal braces: \{name\}"
let lines = "first\nsecond"
let symbol = "\u{1F642}"
```

Strings are never normalized: `"é"` and `"e\u{301}"` are distinct values. [Equality](../types/equality-and-hashing.md) compares contents exactly.

## Interpolation

An unescaped `{` opens an embedded [expression](expressions.md) closed by its matching `}`. Calls and nested literals are allowed. Empty expressions, format suffixes, comments, and newlines are rejected. Escape both braces for JSON-like text: `"\{\"a\": 1\}"`.

```manuscript
let name = "Ada"
let count = 3
let greeting = "Welcome, {name}!"
let calculated = "Next: {count + 1}"
```

Embedded expressions evaluate once, left to right, each formatted before the next. Propagation or a fault stops the rest. Every value is formattable using the same conversion as `toString()`; interpolation adds no implicit conversions elsewhere.

## Converting values to String

Every value has a built-in `toString() String`, needing no import or bound. A bound method keeps its receiver:

```manuscript
fn text[T](value: T) String:
    return value.toString()

test "string conversion":
    let count = 3
    let convert: fn() String = count.toString
    let direct = count.toString()
    let bound = convert()
    let embedded = "{count}"
```

Each conversion produces `"3"`. Passing an Int to a String parameter still needs `.toString()`.

The built-in method wins over any field or interface operation named `toString` and cannot be overridden. Conversion never calls user-defined formatting or resource operations; a closed resource is still printable.

## Indexing and character boundaries

There is no `text[index]` or slice syntax. Byte positions, scalars, and graphemes differ: `"é"` is two UTF-8 bytes; `"e\u{301}"` is two scalars and may display as one grapheme. Grapheme indexing is unsupported.

- `at`, `scalar_at`, `index_of`, `last_index_of`, `slice`, and `slice_scalars` use scalar indexes. `at` returns a one-scalar String; `scalar_at` its code point. Negative indexes count from the end; out of range gives `none`.
- Searches return the first or last scalar index or `none`. An empty search matches at 0 (`index_of`) or `scalar_length()` (`last_index_of`).
- `length()` and `scalar_length()` count scalars; `is_empty()` tests for zero.
- `chars()` returns a fresh `List[String]`; `scalar_values()` returns code points.
- `reverse()` reverses scalars without normalization: `"e\u{301}".reverse()` is `"\u{301}e"`.
- `compare(other:)` returns `-1`, `0`, or `1` by scalar order, case-sensitive, a prefix first: `"Z".compare("a")` is `-1`; `"é".compare("e\u{301}")` is `1`.
- `lines()` splits at LF or CRLF, drops those terminators, keeps interior empty lines and lone CRs, and adds no item for a final newline: `"a\r\nb\n".lines()` is `["a", "b"]`, `"\n\n".lines()` is `["", ""]`, `"a\r".lines()` is `["a\r"]`.
- `lines()` and `chars()` return fresh mutable lists on every call.

### Half-open slices

All slice operations include `start` and exclude `end`. Let `n` be the receiver's scalar, element, or byte length:

| Operation | Bounds and result |
| --- | --- |
| `String.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return `StringError.OutOfRange`. |
| `String.slice_scalars(start:, end:)` | Require `0 <= start <= end <= n` with no relative negative bounds; invalid bounds return `StringError.OutOfRange`. |
| `List.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return `CollectionError.OutOfRange`; success is a new shallow List with independent outer storage. |
| `Bytes.slice(start:, end:)` | Add `n` to each negative bound, then require `0 <= start <= end <= n`. Invalid bounds return `CollectionError.OutOfRange`; success is immutable Bytes that may share immutable storage. |

Equal bounds give an empty range. Bounds are never clamped or swapped; `text.slice(start: 0, end: n + 1)` is an `OutOfRange` error, not a fault. `"aé🙂z".slice(start: -2, end: 4)` is `ok("🙂z")`; `slice(start: 3, end: 1)` and `slice(start: 1, end: 10)` are `error(StringError.OutOfRange)`. See the [String](../../standard-library/reference/prelude.md#string), [collection](../../standard-library/reference/collections.md), and [Bytes](../../standard-library/reference/bytes.md) references.

## Encoding and parsing

| Receiver or constructor | Signature/result |
| --- | --- |
| `String` | `byte_length() Int`; `to_bytes() Bytes`; `parse_int() Optional[Int]` |
| `Bytes(values: List[Int])` | Immutable bytes; each value must be 0–255, otherwise a programming fault |
| `Bytes` | `length() Int`; `at(index: Int) Optional[Int]`; `concat(values: Bytes) Bytes` |
| `Bytes` | `to_string() Optional[String]` |
| `Bytes` | `values() List[Int]`; a fresh mutable list of unsigned byte values |

`to_bytes` encodes UTF-8. `Bytes.to_string` succeeds exactly for valid UTF-8 and returns `none` otherwise. Byte `at` returns the unsigned byte as Int.

`Bytes(values:)` copies its list, and `data.values()` (like the free function `values(data:)` in `@std/bytes.ms`) returns a fresh copy; editing either never changes the Bytes. `values` is a method, not a data field.

`parse_int` accepts an optional ASCII `+` or `-` then one or more ASCII digits, in range. Leading zeros are fine; whitespace, separators, fractions, exponents, and trailing characters give `none`. Exact signatures are in the [API reference](../../standard-library/reference/_index.md). Grapheme and locale operations are unsupported.

```manuscript
import panic from "@std/faults.ms"

import Bytes from "@std/bytes.ms"

test "explicit byte conversion":
    if not ("é".byte_length() == 2):
        return panic("check failed")
    if not ("é".to_bytes().to_string() == some("é")):
        return panic("check failed")
    let invalid: Optional[String] = none
    if not (Bytes([255]).to_string() == invalid):
        return panic("check failed")
    if not ("-007".parse_int() == some(-7)):
        return panic("check failed")
```

## Deterministic formatting

Formatting never depends on locale or host settings.

| Type | Formatting |
| --- | --- |
| String | Contents unchanged; inserted braces/quotes are ordinary output characters and are not parsed again |
| Bool | `true` or `false` |
| Unit | `unit` |
| Int | Base-ten digits, optional leading minus, no separators or leading zeros |
| Float | Shortest round-trip decimal under the rule below; signed zero retains its sign |
| Decimal | Exact numerical decimal value, normalized as below; no significance/scale padding |
| Record | `Type(field: value, ...)`, with fields sorted by name and values recursively converted |
| Alternative | `Type.Case` for a nullary case; `Type.Case(value, ...)` for payloads in declaration order |
| Optional | `Optional.some(value)` or `Optional.none`; for example, `some(42)` formats as `Optional.some(42)` |
| Result | `Result.ok(value)` or `Result.error(cause)`; for example, `ok(42)` formats as `Result.ok(42)` |
| List | `[value, ...]` in element order |
| Map | `Map(key: value, ...)` in insertion order |
| Set | `Set(value, ...)` in insertion order |
| Bytes | `Bytes(byte, ...)`, with each byte in base ten; no UTF-8 decoding |
| Interface view | Conversion of its underlying receiver |
| Function | `[function]`, including bound methods; the function is not called |
| Duration | Signed nanoseconds followed by `ns`, such as `2000000ns` |
| Instant | `Instant(tick)`, with its nanosecond tick in base ten |
| OperationId | `OperationId(number)`, with its number in base ten |
| BigInt | Base-ten integer digits |
| Timestamp | UTC RFC 3339 text with fractional seconds as needed |
| Regex | Pattern text |
| Other opaque native values, authorities, and resources | `[object]`; internal state and addresses are not inspected |

Record and alternative names omit modules and type arguments. Nested Strings are unquoted. Empty values keep their delimiters: `[]`, `Map()`, `Type()`. These forms are for display, not serialization. At nesting depth 64 conversion emits `...`; the outer value is depth 0, and each field, payload, item, key/value, or interface receiver adds one.

**Float.** Choose the shortest decimal that converts back to the same binary64 (nearest, ties to even); among equal lengths take the closest to the exact value, then the even final digit. Strip trailing zeros. Zero is `0`, negative zero `-0`.

**Decimal.** Use the exact value, strip trailing zeros, and apply the same placement rule. Any zero is `0`; `1.00d` formats as `1`. For fixed places use [`to_fixed`](numbers-and-booleans.md#scale-rounding-and-fixed-places): `25.50d.to_fixed(digits: 2)` is `ok("25.50")`.

**Placement.** With `e` the base-ten exponent of the first nonzero digit, use plain notation when -6 ≤ e ≤ 20. Otherwise write one digit, then any remaining digits after a point, then `e`, an explicit sign, and the exponent without leading zeros: `0.000001` is plain, `1e-7` and `1e+21` are not.

Non-finite Floats format as `NaN`, `Infinity`, or `-Infinity` (see [numeric rules](numbers-and-booleans.md#runtime-numeric-outcomes)); they have no literal spelling.
